import Foundation
import ClipHatCore

var assertions = 0
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    assertions += 1
    if try !condition() { throw NSError(domain: "ClipHatChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "FAIL: \(message)"]) }
}
func run() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipHatChecks-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.sqlite")
    func insert(_ db: HistoryDatabase, _ text: String, _ time: Double, limit: Int = 500) throws {
        try db.insert(kind: .text, text: text, image: nil, fingerprint: text, source: "test.app", date: Date(timeIntervalSince1970: time), limit: limit)
    }
    var first: HistoryDatabase? = try HistoryDatabase(url: url)
    try insert(first!, "first", 1)
    let id = try first!.items()[0].id
    try first!.setPinned(id: id, pinned: true, limit: 500)
    try insert(first!, "second", 2); try insert(first!, "first", 3)
    first = nil
    let db = try HistoryDatabase(url: url)
    let reopened = try db.items()
    try expect(reopened.count == 2, "deduplication survives restart")
    try expect(reopened[0].id == id && reopened[0].pinned, "duplicate promotion preserves pin and ID")
    try expect(reopened[0].copiedAt == Date(timeIntervalSince1970: 3), "duplicate promoted to latest date")
    try insert(db, "new", 4, limit: 2)
    try expect(db.items().compactMap(\.text) == ["new", "first"], "oldest unpinned item evicted")
    try db.trim(limit: 0)
    try expect(db.items().count == 1, "pins survive limits smaller than pin count")
    try db.clear(includePinned: false)
    try expect(db.items().count == 1, "clear unpinned preserves pins")
    try db.clear(includePinned: true)
    try expect(db.items().isEmpty, "clear all removes pins")
    let data = Data([0, 1, 2, 3, 255])
    try db.insert(kind: .image, text: nil, image: data, fingerprint: "image", source: nil, limit: 500)
    let image = try db.items()[0]
    try expect(image.kind == .image && image.text == nil, "image metadata")
    try expect(db.imageData(id: image.id) == data, "image bytes round trip")
    try db.delete(id: image.id)
    try expect(db.imageData(id: image.id) == nil, "deleted image bytes removed")
    try db.insert(kind: .audio, text: "/tmp/sample.wav", image: data, fingerprint: "audio-file", source: nil,
                  filename: "sample.wav", limit: 500)
    try expect(db.items()[0].kind == .audio, "audio metadata round trips")
    try db.delete(id: db.items()[0].id)
    try insert(db, "A Café in Rome", 5)
    let text = try db.items()[0]
    try expect(text.matches("CAFÉ") && text.matches("cafe") && text.matches(""), "case-insensitive substring search")
    try expect(!text.matches("Milan"), "nonmatching search")
    for marker in PrivacyPolicy.sensitiveTypes {
        try expect(!PrivacyPolicy.shouldCapture(types: ["public.utf8-plain-text", marker], sources: [], ignoredApps: []), "sensitive marker \(marker) rejected")
    }
    try expect(!PrivacyPolicy.shouldCapture(types: [], sources: ["editor", "passwords"], ignoredApps: ["passwords"]), "declared source excluded")
    try expect(!PrivacyPolicy.shouldCapture(types: [], sources: ["passwords", "editor"], ignoredApps: ["passwords"]), "foreground source excluded")
    try expect(PrivacyPolicy.shouldCapture(types: ["public.png"], sources: ["editor"], ignoredApps: ["passwords"]), "ordinary content accepted")
    try insert(db, "before\0after", 5.5)
    try expect(db.items()[0].text == "before\0after", "embedded NUL bytes preserved")
    // Text containing SQL metacharacters must be treated as data.
    try insert(db, "'); DROP TABLE history; --", 6)
    try expect(db.items().count == 3, "SQL metacharacters are safe")
    print("Passed \(assertions) checks: persistence, deduplication, pins, eviction, clear, image storage, search, and privacy.")
}
do { try run() } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
