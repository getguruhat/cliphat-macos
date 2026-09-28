import AppKit
import AVFoundation
import ClipHatCore
import CryptoKit
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var error: String?
    private let queue = DispatchQueue(label: "com.guruhat.ClipHat.history", qos: .userInitiated)
    private var database: HistoryDatabase?
    private let thumbnails = NSCache<NSNumber, NSImage>()
    func exportURL(for item: ClipboardItem) throws -> URL {
        guard let data = try queue.sync(execute: { try database?.imageData(id: item.id) }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipHat Exports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let filename = ((item.filename ?? "ClipHat Image \(item.id).png") as NSString).lastPathComponent
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
    init(url: URL? = nil) {
        thumbnails.countLimit = 80
        let location = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GuruHat/ClipHat/history.sqlite")
        queue.async { [self] in
            // Keep recent exports alive for receiving apps, then reclaim them
            // on a later launch. Only this app's UUID export directories qualify.
            let exports = FileManager.default.temporaryDirectory.appendingPathComponent("ClipHat Exports", isDirectory: true)
            if let entries = try? FileManager.default.contentsOfDirectory(at: exports, includingPropertiesForKeys: [.creationDateKey]) {
                for entry in entries where UUID(uuidString: entry.lastPathComponent) != nil {
                    if let created = try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       created < Date(timeIntervalSinceNow: -86400) {
                        try? FileManager.default.removeItem(at: entry)
                    }
                }
            }
            do { database = try HistoryDatabase(url: location); try publish() }
            catch { report(error) }
        }
    }
    func flush() { queue.sync {} }
    func captureFile(_ url: URL, kind: ContentKind, source: String?, limit: Int) {
        change { db in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            let maximum = (kind == .image ? 10 : 20) * 1024 * 1024
            guard values.isRegularFile == true, let size = values.fileSize, size <= maximum else {
                throw NSError(domain: "ClipHat", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent): unsupported file or size limit exceeded."])
            }
            let data = try Data(contentsOf: url)
            guard data.count <= maximum else { throw CocoaError(.fileReadTooLarge) }
            let fingerprint = kind.rawValue + ":" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try db.insert(kind: kind, text: url.path, image: data, fingerprint: fingerprint,
                          source: source, filename: url.lastPathComponent, limit: limit)
        }
    }
    private func report(_ failure: Error) {
        DispatchQueue.main.async { self.error = "History could not be saved or read: \(failure.localizedDescription)" }
    }
    private func publish() throws {
        guard let database else { return }
        let records = try database.items()
        DispatchQueue.main.async { self.items = records }
    }
    private func change(_ operation: @escaping (HistoryDatabase) throws -> Void) {
        queue.async { [self] in
            guard let database else { return }
            do { try operation(database); try publish() } catch { report(error) }
        }
    }
    func capture(kind: ContentKind, text: String?, image: Data?, source: String?, filename: String? = nil, limit: Int) {
        change { db in
            let data = image ?? Data((text ?? "").utf8)
            let fingerprint = kind.rawValue + ":" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try db.insert(kind: kind, text: text, image: image, fingerprint: fingerprint, source: source,
                          filename: filename, limit: limit)
        }
    }
    func pin(_ item: ClipboardItem, limit: Int) { change { try $0.setPinned(id: item.id, pinned: !item.pinned, limit: limit) } }
    func delete(_ item: ClipboardItem) { thumbnails.removeObject(forKey: NSNumber(value: item.id)); change { try $0.delete(id: item.id) } }
    func clear(includePinned: Bool) { thumbnails.removeAllObjects(); change { try $0.clear(includePinned: includePinned) } }
    func trim(limit: Int) { change { try $0.trim(limit: limit) } }
    func imageData(for item: ClipboardItem, completion: @escaping (Data?) -> Void) {
        queue.async { [self] in
            do { let data = try database?.imageData(id: item.id); DispatchQueue.main.async { completion(data) } }
            catch { report(error); DispatchQueue.main.async { completion(nil) } }
        }
    }
    func thumbnail(for item: ClipboardItem, completion: @escaping (NSImage?) -> Void) {
        if let cached = thumbnails.object(forKey: NSNumber(value: item.id)) { completion(cached); return }
        queue.async { [self] in
            do {
                guard let data = try database?.imageData(id: item.id) else { return }
                let image: NSImage?
                if item.kind == .document || item.kind == .audio {
                    let filename = item.filename ?? "ClipHat Document"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClipHat Preview \(item.id)-\(UUID().uuidString)-\(filename)")
                    try data.write(to: url, options: .atomic)
                    let request = QLThumbnailGenerator.Request(fileAt: url, size: NSSize(width: 360, height: 360), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
                    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                        defer { try? FileManager.default.removeItem(at: url) }
                        let generated = representation.map { NSImage(cgImage: $0.cgImage, size: $0.contentRect.size) }
                        if let generated { self.thumbnails.setObject(generated, forKey: NSNumber(value: item.id)) }
                        DispatchQueue.main.async { completion(generated) }
                    }
                    return
                } else {
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                              kCGImageSourceThumbnailMaxPixelSize: 360, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return }
                    image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
                guard let image else { return }
                thumbnails.setObject(image, forKey: NSNumber(value: item.id))
                DispatchQueue.main.async { completion(image) }
            } catch { report(error) }
        }
    }
    func metadata(for item: ClipboardItem, completion: @escaping (String) -> Void) {
        switch item.kind {
        case .text:
            let count = item.text?.count ?? 0
            completion("Text · \(count) character\(count == 1 ? "" : "s")")
        case .link:
            let host = item.text.flatMap(URL.init(string:))?.host ?? "Link"
            completion("Link · \(host)")
        case .document:
            let ext = item.filename.flatMap { URL(fileURLWithPath: $0).pathExtension.uppercased() } ?? "FILE"
            completion("Document · \(ext)")
        case .audio:
            let ext = item.filename.flatMap { URL(fileURLWithPath: $0).pathExtension.uppercased() } ?? "AUDIO"
            queue.async { [self] in
                do {
                    guard let data = try database?.imageData(id: item.id) else {
                        DispatchQueue.main.async { completion("Audio · \(ext)") }; return
                    }
                    let suffix = item.filename.map { "." + URL(fileURLWithPath: $0).pathExtension } ?? ""
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ClipHat Audio \(item.id)-\(UUID().uuidString)\(suffix)")
                    try data.write(to: url, options: .atomic)
                    let asset = AVURLAsset(url: url)
                    Task {
                        defer { try? FileManager.default.removeItem(at: url) }
                        let time = try? await asset.load(.duration)
                        let seconds = time.map(CMTimeGetSeconds)
                        let duration = seconds.flatMap { $0.isFinite && $0 >= 0 ? Self.audioDuration($0) : nil }
                        await MainActor.run {
                            completion(["Audio", ext, duration].compactMap { $0 }.joined(separator: " · "))
                        }
                    }
                } catch {
                    DispatchQueue.main.async { completion("Audio · \(ext)") }
                }
            }
        case .image:
            queue.async { [self] in
                do {
                    guard let data = try database?.imageData(id: item.id),
                          let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                        DispatchQueue.main.async { completion("Image") }; return
                    }
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                    let width = properties?[kCGImagePropertyPixelWidth] as? Int
                    let height = properties?[kCGImagePropertyPixelHeight] as? Int
                    let identifier = CGImageSourceGetType(source) as String?
                    let type = identifier?.split(separator: ".").last?.uppercased() ?? "IMAGE"
                    let dimensions = width.flatMap { width in height.map { "\(width) × \($0)" } } ?? "Image"
                    DispatchQueue.main.async { completion("\(dimensions) · \(type)") }
                } catch {
                    DispatchQueue.main.async { completion("Image") }
                }
            }
        }
    }
    private static func audioDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, remaining)
                         : String(format: "%d:%02d", minutes, remaining)
    }
    func dragProvider(for item: ClipboardItem) -> NSItemProvider {
        if item.kind == .document || item.kind == .audio || item.kind == .image {
            do {
                let url = try exportURL(for: item)
                guard let provider = NSItemProvider(contentsOf: url) else { throw CocoaError(.fileReadUnknown) }
                provider.suggestedName = url.deletingPathExtension().lastPathComponent
                return provider
            } catch { report(error); return NSItemProvider() }
        }
        switch item.kind {
        case .text:
            let provider = NSItemProvider(object: (item.text ?? "") as NSString)
            provider.suggestedName = "ClipHat Text.txt"
            provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
                completion(Data((item.text ?? "").utf8), nil)
                return nil
            }
            registerExport(on: provider, item: item, type: .plainText, filename: "ClipHat Text \(item.id).txt") {
                Data((item.text ?? "").utf8)
            }
            return provider
        case .link:
            if let value = item.text, let url = URL(string: value) {
                let provider = NSItemProvider(object: url as NSURL)
                provider.suggestedName = "\(url.host ?? "ClipHat Link").webloc"
                provider.registerDataRepresentation(forTypeIdentifier: UTType.url.identifier, visibility: .all) { completion in
                    completion(Data(value.utf8), nil)
                    return nil
                }
                registerExport(on: provider, item: item, type: UTType("com.apple.web-internet-location") ?? .url,
                               filename: "ClipHat Link \(item.id).webloc") {
                    try PropertyListSerialization.data(fromPropertyList: ["URL": value], format: .xml, options: 0)
                }
                return provider
            }
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .document, .audio, .image:
            return NSItemProvider() // File cases are handled above.
        }
    }
    private func registerExport(on provider: NSItemProvider, item: ClipboardItem, type: UTType,
                                filename: String, data: @escaping () throws -> Data) {
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { [weak self] completion in
            let progress = Progress(totalUnitCount: 1)
            guard let self else {
                completion(nil, false, CocoaError(.fileNoSuchFile)); return progress
            }
            self.queue.async {
                do {
                    let directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ClipHat Exports", isDirectory: true)
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let url = directory.appendingPathComponent(filename)
                    try data().write(to: url, options: .atomic)
                    progress.completedUnitCount = 1
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return progress
        }
    }
}
