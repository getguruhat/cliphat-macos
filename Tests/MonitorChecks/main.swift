import AppKit
import ClipHatCore
import UniformTypeIdentifiers

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipHatMonitorChecks-\(UUID())")
let domain = "ClipHatMonitorChecks.\(UUID())"
let defaults = UserDefaults(suiteName: domain)!
let preferences = Preferences(defaults: defaults)
let store = ClipboardStore(url: directory.appendingPathComponent("history.sqlite"))
let pasteboard = NSPasteboard.withUniqueName()
let monitor = ClipboardMonitor(store: store, preferences: preferences, pasteboard: pasteboard)
var checks = 0
func drain() {
    store.flush()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
expect(preferences.panelPosition == .left, "panel position defaults to left")
for position in PanelPosition.allCases {
    preferences.panelPosition = position
    let reloaded = Preferences(defaults: defaults)
    expect(reloaded.panelPosition == position, "persists \(position.rawValue) panel position")
}
func copy(_ text: String, marker: String? = nil, source: String? = nil) {
    let item = NSPasteboardItem(); item.setString(text, forType: .string)
    if let marker { item.setData(Data(), forType: .init(marker)) }
    if let source { item.setString(source, forType: .init("org.nspasteboard.source")) }
    pasteboard.clearContents(); pasteboard.writeObjects([item]); monitor.poll(); drain()
}
drain()
copy("ClipHat test text")
expect(store.items.count == 1 && store.items[0].text == "ClipHat test text", "captures plain text")
copy("ClipHat test text")
expect(store.items.count == 1, "deduplicates pasteboard writes")
copy("https://example.com/cliphat")
expect(store.items.first?.kind == .link, "recognizes URLs")
// Modern NSPasteboard rejects the legacy non-UTI name; the pure-policy test covers it.
for marker in PrivacyPolicy.sensitiveTypes where marker != "Pasteboard generator type" { copy("secret", marker: marker) }
expect(store.items.count == 2, "monitor excludes sensitive markers")
preferences.ignoredApps.insert("test.ignored")
copy("ignored content", source: "test.ignored")
expect(store.items.count == 2, "monitor honors declared source exclusions")
preferences.paused = true; copy("paused")
preferences.paused = false; monitor.acknowledgeChange(); monitor.poll(); drain()
expect(store.items.count == 2, "pause and resume do not import skipped content")
preferences.storeLinks = false; copy("https://example.com/skipped")
expect(store.items.count == 2, "disabled links are not captured as text")
preferences.storeText = false; copy("disabled text")
expect(store.items.count == 2, "disabled text is skipped")
preferences.storeText = true
let textItem = store.items.first { $0.kind == .text }!
expect(store.dragProvider(for: textItem).hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
       "text items expose a native drag representation")
let linkItem = store.items.first { $0.kind == .link }!
expect(store.dragProvider(for: linkItem).hasItemConformingToTypeIdentifier(UTType.url.identifier),
       "links expose a native URL drag representation")
var restored = false
monitor.restore(textItem) { restored = $0 }; monitor.poll(); drain()
expect(restored && pasteboard.string(forType: .string) == "ClipHat test text", "restores text")
expect(store.items.count == 2, "does not recapture own restoration")
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let png = bitmap.representation(using: .png, properties: [:])!
pasteboard.clearContents(); pasteboard.setData(png, forType: .png); monitor.poll(); drain()
expect(store.items.first?.kind == .image, "captures PNG")
let imageItem = store.items.first!
restored = false
monitor.restore(imageItem) { restored = $0 }; drain()
expect(restored && pasteboard.data(forType: .png) == png, "restores original PNG bytes")
let imageProvider = store.dragProvider(for: imageItem)
expect(imageProvider.hasItemConformingToTypeIdentifier(UTType.png.identifier),
       "images expose a native file drag representation")
var draggedImage: Data?
var dragFinished = false
imageProvider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, _ in
    if let url { draggedImage = try? Data(contentsOf: url) }
    dragFinished = true
}
let dragDeadline = Date(timeIntervalSinceNow: 2)
while !dragFinished && Date() < dragDeadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
expect(draggedImage == png, "image drag provides the original full-resolution bytes")
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35)); drain()
expect(store.items.contains(where: { $0.id == imageItem.id }), "export preserves history even if the drag is canceled")
let copiedImageURL = directory.appendingPathComponent("finder-image.png")
try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
try! png.write(to: copiedImageURL)
pasteboard.clearContents(); pasteboard.writeObjects([copiedImageURL as NSURL]); monitor.poll(); drain()
expect(store.items.first?.kind == .image, "Finder image files are captured as images")
let finderImageItem = store.items.first!
expect(finderImageItem.filename == "finder-image.png", "Finder image filenames are preserved")
restored = false
monitor.restore(finderImageItem) { restored = $0 }; drain()
expect(restored && pasteboard.data(forType: .png) == png,
       "Finder image files preserve their actual preview bytes")
let finderProvider = store.dragProvider(for: finderImageItem)
expect(finderProvider.suggestedName == "finder-image", "Finder exports do not duplicate the extension")
var exportedFilename: String?
var finderDragFinished = false
finderProvider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, _ in
    exportedFilename = url?.lastPathComponent
    finderDragFinished = true
}
let finderDragDeadline = Date(timeIntervalSinceNow: 2)
while !finderDragFinished && Date() < finderDragDeadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
expect(exportedFilename == "finder-image.png", "Finder exports use the original filename")
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35)); drain()
preferences.storeImages = false
let countBeforeDisabledImage = store.items.count
pasteboard.clearContents(); pasteboard.setData(png, forType: .png); monitor.poll(); drain()
expect(store.items.count == countBeforeDisabledImage, "disabled images skipped")
let docA = directory.appendingPathComponent("a/report.csv")
let docB = directory.appendingPathComponent("b/report.csv")
try! FileManager.default.createDirectory(at: docA.deletingLastPathComponent(), withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: docB.deletingLastPathComponent(), withIntermediateDirectories: true)
try! Data("first,document".utf8).write(to: docA)
try! Data("second,document".utf8).write(to: docB)
pasteboard.clearContents(); pasteboard.writeObjects([docA as NSURL, docB as NSURL]); monitor.poll(); drain()
let documents = store.items.filter { $0.kind == .document }
expect(documents.count == 2, "multiple documents are captured separately")
let firstDocument = documents.first { $0.text == docA.path }!
let secondDocument = documents.first { $0.text == docB.path }!
let exportA = try! store.exportURL(for: firstDocument)
let exportB = try! store.exportURL(for: secondDocument)
expect(exportA != exportB && (try! Data(contentsOf: exportA)) == Data("first,document".utf8), "same-name exports cannot overwrite each other")
restored = false
monitor.restore(firstDocument) { restored = $0 }; drain()
let restoredURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
expect(restored && restoredURLs?.first.flatMap { try? Data(contentsOf: $0) } == Data("first,document".utf8), "document paste restores a real file")
let movedDocument = directory.appendingPathComponent("moved.csv")
try! Data("first,document".utf8).write(to: movedDocument)
pasteboard.clearContents(); pasteboard.writeObjects([movedDocument as NSURL]); monitor.poll(); drain()
expect(store.items.first { $0.id == firstDocument.id }?.text == movedDocument.path, "recopy updates the original file path")
expect(store.error == nil, "no persistence errors")
let audioURL = directory.appendingPathComponent("sample.wav")
try! Data("test audio bytes".utf8).write(to: audioURL)
pasteboard.clearContents(); pasteboard.writeObjects([audioURL as NSURL]); monitor.poll(); drain()
let audioItem = store.items.first { $0.kind == .audio }
expect(audioItem?.filename == "sample.wav", "audio files are categorized separately from documents")
if let audioItem {
    restored = false
    monitor.restore(audioItem) { restored = $0 }; drain()
    expect(restored, "audio paste restores a real file")
}
preferences.storeDocuments = false
let beforeDisabledDocument = store.items.count
let disabledURL = directory.appendingPathComponent("disabled.txt")
try! Data("disabled document".utf8).write(to: disabledURL)
pasteboard.clearContents(); pasteboard.writeObjects([disabledURL as NSURL]); monitor.poll(); drain()
expect(store.items.count == beforeDisabledDocument, "document capture honors its own preference")
preferences.storeDocuments = true
let invalidFile = NSPasteboardItem()
invalidFile.setString(directory.absoluteString, forType: .fileURL)
invalidFile.setData(png, forType: .tiff)
pasteboard.clearContents(); pasteboard.writeObjects([invalidFile]); monitor.poll(); drain()
expect(store.items.count == beforeDisabledDocument && store.error != nil, "unsupported folders never fall back to preview images")
pasteboard.releaseGlobally(); defaults.removePersistentDomain(forName: domain)
try? FileManager.default.removeItem(at: directory)
print("Passed \(checks) monitor checks using an isolated pasteboard and temporary history.")
