import Foundation
import CSQLite

/// Access only on a single serial queue. Image payloads are fetched on demand;
/// the in-memory history contains metadata and text, never full images.
public final class HistoryDatabase {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open history"
            sqlite3_close(db); db = nil
            throw Failure(message: message)
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA secure_delete = ON")
            try execute("PRAGMA auto_vacuum = INCREMENTAL")
            try execute("CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, text TEXT, copied REAL NOT NULL, source TEXT, pinned INTEGER NOT NULL DEFAULT 0, fingerprint TEXT NOT NULL UNIQUE, image BLOB, filename TEXT)")
            if try !hasColumn("filename", in: "history") { try execute("ALTER TABLE history ADD COLUMN filename TEXT") }
            // Audio files captured by older releases were stored as documents.
            try execute("UPDATE history SET kind='audio', fingerprint='audio:' || substr(fingerprint, 10) WHERE kind='document' AND (lower(filename) GLOB '*.aac' OR lower(filename) GLOB '*.aif' OR lower(filename) GLOB '*.aiff' OR lower(filename) GLOB '*.alac' OR lower(filename) GLOB '*.caf' OR lower(filename) GLOB '*.flac' OR lower(filename) GLOB '*.m4a' OR lower(filename) GLOB '*.m4b' OR lower(filename) GLOB '*.mp3' OR lower(filename) GLOB '*.oga' OR lower(filename) GLOB '*.ogg' OR lower(filename) GLOB '*.opus' OR lower(filename) GLOB '*.wav' OR lower(filename) GLOB '*.wave' OR lower(filename) GLOB '*.wma')")
            try execute("CREATE INDEX IF NOT EXISTS history_date ON history(copied DESC)")
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func failure() -> Failure { Failure(message: String(cString: sqlite3_errmsg(db))) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func hasColumn(_ column: String, in table: String) throws -> Bool {
        let s = try statement("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(s) }
        while sqlite3_step(s) == SQLITE_ROW {
            if string(s, 1) == column { return true }
        }
        return false
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &result, nil) == SQLITE_OK, let result else { throw failure() }
        return result
    }
    private func bind(_ value: String?, to s: OpaquePointer, at index: Int32) {
        if let value { sqlite3_bind_text(s, index, value, Int32(value.utf8.count), transient) }
        else { sqlite3_bind_null(s, index) }
    }
    private func string(_ s: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_text(s, index).map { String(decoding: UnsafeBufferPointer(start: $0, count: Int(sqlite3_column_bytes(s, index))), as: UTF8.self) }
    }
    private func finish(_ s: OpaquePointer) throws {
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
    }
    public func items() throws -> [ClipboardItem] {
        let s = try statement("SELECT id,kind,text,copied,source,pinned,fingerprint,filename FROM history ORDER BY copied DESC,id DESC")
        defer { sqlite3_finalize(s) }
        var result: [ClipboardItem] = []
        var status = sqlite3_step(s)
        while status == SQLITE_ROW {
            if let kind = string(s, 1).flatMap(ContentKind.init(rawValue:)) {
                result.append(ClipboardItem(id: sqlite3_column_int64(s, 0), kind: kind, text: string(s, 2),
                    copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 3)), source: string(s, 4), filename: string(s, 7),
                    pinned: sqlite3_column_int(s, 5) != 0, fingerprint: string(s, 6) ?? ""))
            }
            status = sqlite3_step(s)
        }
        guard status == SQLITE_DONE else { throw failure() }
        return result
    }
    public func insert(kind: ContentKind, text: String?, image: Data?, fingerprint: String, source: String?,
                       filename: String? = nil, date: Date = Date(), limit: Int) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let s = try statement("INSERT INTO history(kind,text,copied,source,fingerprint,image,filename) VALUES(?,?,?,?,?,?,?) ON CONFLICT(fingerprint) DO UPDATE SET text=excluded.text,copied=excluded.copied,source=excluded.source,filename=COALESCE(excluded.filename,history.filename)")
            defer { sqlite3_finalize(s) }
            bind(kind.rawValue, to: s, at: 1); bind(text, to: s, at: 2)
            sqlite3_bind_double(s, 3, date.timeIntervalSince1970); bind(source, to: s, at: 4)
            bind(fingerprint, to: s, at: 5)
            if let image { _ = image.withUnsafeBytes { sqlite3_bind_blob(s, 6, $0.baseAddress, Int32(image.count), transient) } }
            bind(filename, to: s, at: 7)
            try finish(s)
            try trim(limit: limit)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func trim(limit: Int) throws {
        // Pinned entries count toward the limit but are never evicted.
        let capacity = max(0, limit)
        try execute("DELETE FROM history WHERE id IN (SELECT id FROM history WHERE pinned=0 ORDER BY copied DESC,id DESC LIMIT -1 OFFSET MAX(0,\(capacity)-(SELECT COUNT(*) FROM history WHERE pinned=1)))")
        // Bound unpinned image storage to 200 MiB in addition to the item limit.
        try execute("DELETE FROM history WHERE id IN (SELECT id FROM (SELECT id,SUM(length(image)) OVER (ORDER BY copied DESC,id DESC) AS bytes FROM history WHERE pinned=0 AND image IS NOT NULL) WHERE bytes > 209715200)")
    }
    public func imageData(id: Int64) throws -> Data? {
        let s = try statement("SELECT image FROM history WHERE id=?")
        defer { sqlite3_finalize(s) }; sqlite3_bind_int64(s, 1, id)
        let status = sqlite3_step(s)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw failure() }
        guard let bytes = sqlite3_column_blob(s, 0) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, 0)))
    }
    public func setPinned(id: Int64, pinned: Bool, limit: Int) throws {
        let s = try statement("UPDATE history SET pinned=? WHERE id=?")
        defer { sqlite3_finalize(s) }; sqlite3_bind_int(s, 1, pinned ? 1 : 0); sqlite3_bind_int64(s, 2, id)
        try finish(s); try trim(limit: limit)
    }
    public func delete(id: Int64) throws {
        let s = try statement("DELETE FROM history WHERE id=?")
        defer { sqlite3_finalize(s) }; sqlite3_bind_int64(s, 1, id); try finish(s)
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }
    public func clear(includePinned: Bool) throws {
        try execute(includePinned ? "DELETE FROM history" : "DELETE FROM history WHERE pinned=0")
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try execute("VACUUM")
    }
}
