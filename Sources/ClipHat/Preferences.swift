import AppKit
import SwiftUI
import ServiceManagement
import ClipHatCore

enum PanelPosition: String, CaseIterable, Codable, Identifiable {
    case left, right, top, bottom

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var tooltip: String { "Open from \(rawValue)" }
    var isHorizontal: Bool { self == .top || self == .bottom }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var limit: Int { didSet { let valid = min(5000, max(10, limit)); if limit != valid { limit = valid }; defaults.set(limit, forKey: "historyLimit"); onLimitChange?() } }
    @Published var storeText: Bool { didSet { defaults.set(storeText, forKey: "storeText") } }
    @Published var storeLinks: Bool { didSet { defaults.set(storeLinks, forKey: "storeLinks") } }
    @Published var storeImages: Bool { didSet { defaults.set(storeImages, forKey: "storeImages") } }
    @Published var largePreviews: Bool { didSet { defaults.set(largePreviews, forKey: "largePreviews"); onPanelPositionChange?() } }
    @Published var storeDocuments: Bool { didSet { defaults.set(storeDocuments, forKey: "storeDocuments") } }
    @Published var ignoredApps: Set<String> { didSet { defaults.set(Array(ignoredApps), forKey: "ignoredApps") } }
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: "paused"); onPauseChange?() } }
    @Published var panelPinned: Bool { didSet { defaults.set(panelPinned, forKey: "panelPinned") } }
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); onAppearanceChange?() } }
    @Published var panelPosition: PanelPosition {
        didSet {
            defaults.set(panelPosition.rawValue, forKey: "panelPosition")
            onPanelPositionChange?()
        }
    }
    @Published var loginEnabled = false
    @Published var loginMessage = ""
    @Published var shortcutMessage = ""
    var onLimitChange: (() -> Void)?
    var onPauseChange: (() -> Void)?
    var onPanelPositionChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["historyLimit": 500, "storeText": true, "storeLinks": true, "storeImages": true, "storeDocuments": true,
                                     "ignoredApps": Array(PrivacyPolicy.defaultIgnoredApps),
                                     "panelPosition": PanelPosition.left.rawValue,
                                     "appearance": AppAppearance.system.rawValue])
        limit = min(5000, max(10, defaults.integer(forKey: "historyLimit")))
        storeText = defaults.bool(forKey: "storeText"); storeLinks = defaults.bool(forKey: "storeLinks")
        storeImages = defaults.bool(forKey: "storeImages"); paused = defaults.bool(forKey: "paused")
        largePreviews = defaults.bool(forKey: "largePreviews")
        storeDocuments = defaults.bool(forKey: "storeDocuments")
        panelPinned = defaults.bool(forKey: "panelPinned")
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        ignoredApps = Set(defaults.stringArray(forKey: "ignoredApps") ?? [])
        panelPosition = PanelPosition(rawValue: defaults.string(forKey: "panelPosition") ?? "") ?? .left
        refreshLogin()
    }
    func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval { loginMessage = "Allow ClipHat in System Settings → General → Login Items." }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginMessage = ""; refreshLogin()
        } catch { loginMessage = error.localizedDescription; refreshLogin() }
    }
    func addIgnoredApps() {
        let panel = NSOpenPanel()
        panel.title = "Ignore clipboard activity from applications"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls { if let id = Bundle(url: url)?.bundleIdentifier { ignoredApps.insert(id) } }
        }
    }
}
