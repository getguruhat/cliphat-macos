import AppKit
import ImageIO
import ClipHatCore
import UniformTypeIdentifiers

final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let preferences: Preferences
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChange: Int
    init(store: ClipboardStore, preferences: Preferences, pasteboard: NSPasteboard = .general) {
        self.store = store; self.preferences = preferences; self.pasteboard = pasteboard
        lastChange = pasteboard.changeCount // Never import the clipboard from before launch.
    }
    func start() {
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func acknowledgeChange() { lastChange = pasteboard.changeCount }
    private func allowed() -> Bool {
        var types = Set((pasteboard.types ?? []).map(\.rawValue))
        for item in pasteboard.pasteboardItems ?? [] { types.formUnion(item.types.map(\.rawValue)) }
        let source = pasteboard.string(forType: .init("org.nspasteboard.source"))
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return PrivacyPolicy.shouldCapture(types: types, sources: [source, front].compactMap { $0 }, ignoredApps: preferences.ignoredApps)
    }
    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChange else { return }; lastChange = count
        guard !preferences.paused, allowed() else { return }
        let source = pasteboard.string(forType: .init("org.nspasteboard.source"))
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            for url in urls {
                let type = UTType(filenameExtension: url.pathExtension)
                let isImage = type?.conforms(to: .image) == true
                let isAudio = type?.conforms(to: .audio) == true
                guard isImage ? preferences.storeImages : preferences.storeDocuments else { continue }
                guard pasteboard.changeCount == count, allowed() else { return }
                store.captureFile(url, kind: isImage ? .image : (isAudio ? .audio : .document), source: source, limit: preferences.limit)
            }
            return
        }
        var kind: ContentKind = .text
        var text: String?
        var image: Data?
        let filename: String? = nil
        if pasteboard.availableType(from: [.png, .tiff]) != nil {
            guard preferences.storeImages else { return }
            image = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
            guard let data = image, !data.isEmpty, data.count <= 10 * 1024 * 1024 else { return }
            kind = .image
        } else {
            text = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string)
            guard let value = text, !value.isEmpty, value.utf8.count <= 1024 * 1024 else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), ["http", "https", "ftp", "mailto"].contains(url.scheme?.lowercased() ?? ""),
               !trimmed.contains(where: \.isWhitespace) { kind = .link }
            guard kind == .link ? preferences.storeLinks : preferences.storeText else { return }
        }
        // Reject torn reads and markers added while the content was being read.
        guard pasteboard.changeCount == count, allowed(), pasteboard.changeCount == count else { return }
        store.capture(kind: kind, text: text, image: image, source: source, filename: filename, limit: preferences.limit)
    }
    func restore(_ item: ClipboardItem, completion: @escaping (Bool) -> Void) {
        if item.kind == .document || item.kind == .audio {
            do {
                let url = try store.exportURL(for: item)
                pasteboard.clearContents()
                let success = pasteboard.writeObjects([url as NSURL])
                acknowledgeChange(); completion(success)
            } catch { completion(false) }
            return
        }
        let write: (Data?) -> Void = { [self] data in
            let entry = NSPasteboardItem()
            if item.kind == .image {
                guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let type = CGImageSourceGetType(source) else { completion(false); return }
                entry.setData(data, forType: NSPasteboard.PasteboardType(type as String))
            } else {
                guard let text = item.text else { completion(false); return }
                entry.setString(text, forType: .string)
                if item.kind == .link { entry.setString(text, forType: .URL) }
            }
            entry.setString(item.source ?? "", forType: .init("org.nspasteboard.source"))
            pasteboard.clearContents()
            let success = pasteboard.writeObjects([entry]); acknowledgeChange(); completion(success)
        }
        if item.kind == .image { store.imageData(for: item, completion: write) } else { write(nil) }
    }
    deinit { timer?.invalidate() }
}
