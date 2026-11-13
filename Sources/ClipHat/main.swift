import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipboardStore!
    private var preferences: Preferences!
    private var monitor: ClipboardMonitor!
    private var picker: PickerController!
    private var hotKey: HotKeyManager!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let updates = UpdateChecker(appName: "ClipHat", repo: "getguruhat/cliphat-macos")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        preferences = Preferences(); store = ClipboardStore()
        monitor = ClipboardMonitor(store: store, preferences: preferences)
        picker = PickerController(store: store, preferences: preferences, monitor: monitor)
        picker.onShowSettings = { [weak self] in self?.settings() }
        picker.onTogglePause = { [weak self] in self?.togglePause() }
        preferences.onLimitChange = { [weak self] in guard let self else { return }; self.store.trim(limit: self.preferences.limit) }
        preferences.onPauseChange = { [weak self] in self?.monitor.acknowledgeChange(); self?.updateStatus() }
        preferences.onPanelPositionChange = { [weak self] in self?.picker.updatePositionIfVisible() }
        preferences.onAppearanceChange = { [weak self] in
            self?.picker.applyAppearance()
            self?.settingsWindow?.appearance = self?.preferences.appearance.nsAppearance
        }
        hotKey = HotKeyManager(); hotKey.onPress = { [weak self] in self?.picker.toggle() }
        if hotKey.register() != noErr {
            preferences.shortcutMessage = "⌘⇧V is unavailable. Another app may be using it. Open history from the menu bar."
        }
        createEditMenu(); createStatusItem(); monitor.start(); store.trim(limit: preferences.limit)
        if CommandLine.arguments.contains("--show-history") { picker.show() }
        updates.start()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        picker.show(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { store?.flush() }
    func applicationDidResignActive(_ notification: Notification) {
        picker?.keepVisibleWhenInactive()
    }
    private func createEditMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(title: "ClipHat", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "ClipHat")
        add("Settings…", #selector(settings), to: appMenu, key: ",")
        appMenu.addItem(.separator())
        add("Quit ClipHat", #selector(quit), to: appMenu, key: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        item.submenu = edit; menu.addItem(item); NSApp.mainMenu = menu
    }
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleHistory(_:))
        statusItem.button?.isEnabled = true
        updateStatus()
    }
    @discardableResult private func add(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }
    private func updateStatus() {
        let image: NSImage?
        if preferences.paused {
            image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "ClipHat paused")
            image?.isTemplate = true
        } else {
            image = menuBarHatImage()
        }
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = preferences.paused ? "ClipHat — History paused" : "ClipHat — ⌘⇧V"
    }
    private func menuBarHatImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "ClipHatMenuIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipHat")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
    @objc private func toggleHistory(_ sender: NSStatusBarButton) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastStatusItemClick")
        DispatchQueue.main.async { [weak self] in self?.picker.toggle() }
    }
    @objc private func openHistory() { picker.show() }
    @objc private func togglePause() { preferences.paused.toggle() }
    @objc private func clearAll() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "This permanently deletes every saved item, including pinned items. The current macOS clipboard is unchanged."
        alert.alertStyle = .warning; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Clear All History")
        if alert.runModal() == .alertSecondButtonReturn { store.clear(includePinned: true) }
    }
    @objc private func settings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 590), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "ClipHat Settings"; window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
            window.appearance = preferences.appearance.nsAppearance
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, store: store, updates: updates,
                clearAll: { [weak self] in self?.clearAll() }, quit: { [weak self] in self?.quit() }))
            window.center(); settingsWindow = window
        }
        picker.dismissForSettings()
        preferences.refreshLogin(); NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
