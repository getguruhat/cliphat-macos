import AppKit

/// Asks GitHub for the app's latest release a minute after launch and then once a day.
/// When it's newer than this build, `available` holds it and an alert offers the
/// download once per version.
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let version: String
        let page: URL
    }

    /// The alert's text. Templates take {0} like `Strings.fill`.
    struct Wording {
        var title = "{0} {1} is available"
        var message = "You have version {0}. Download the new version from GitHub?"
        var download = "Download"
        var later = "Later"
    }

    @Published private(set) var available: Release?

    private let appName: String
    private let latestURL: URL
    private let wording: Wording
    private var timer: Timer?
    private static let announcedKey = "updateAnnouncedVersion"

    /// - Parameter repo: "owner/name" on GitHub.
    init(appName: String, repo: String, wording: Wording = Wording()) {
        self.appName = appName
        latestURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        self.wording = wording
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        var request = URLRequest(url: latestURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self, (response as? HTTPURLResponse)?.statusCode == 200, let data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return }
            let version = UpdateChecker.version(fromTag: tag)
            guard UpdateChecker.isNewer(version, than: self.currentVersion) else { return }
            DispatchQueue.main.async { self.found(Release(version: version, page: page)) }
        }.resume()
    }

    func open() {
        guard let available else { return }
        NSWorkspace.shared.open(available.page)
    }

    private func found(_ release: Release) {
        available = release
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: UpdateChecker.announcedKey) != release.version else { return }
        defaults.set(release.version, forKey: UpdateChecker.announcedKey)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = UpdateChecker.fill(wording.title, appName, release.version)
        alert.informativeText = UpdateChecker.fill(wording.message, currentVersion)
        alert.addButton(withTitle: wording.download)
        alert.addButton(withTitle: wording.later)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.page) }
    }

    /// "v1.5.2" and "v1.5.2-windows" both give "1.5.2".
    static func version(fromTag tag: String) -> String {
        let trimmed = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        return String(trimmed.prefix { $0.isNumber || $0 == "." })
    }

    /// Compares dotted numbers, so "1.10" is newer than "1.9" and "1.5" equals "1.5.0".
    static func isNewer(_ version: String, than current: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        guard !a.isEmpty else { return false }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func fill(_ template: String, _ values: String...) -> String {
        var text = template
        for (index, value) in values.enumerated() {
            text = text.replacingOccurrences(of: "{\(index)}", with: value)
        }
        return text
    }
}
