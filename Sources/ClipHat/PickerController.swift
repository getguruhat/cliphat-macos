import AppKit
import SwiftUI
import ClipHatCore

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class PickerController: NSObject, NSWindowDelegate {
    let state = PickerState()
    private let store: ClipboardStore
    private let preferences: Preferences
    private let monitor: ClipboardMonitor
    private var panel: NSPanel!
    private var eventMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var resignDismissal: DispatchWorkItem?
    private var closing = false
    var onShowSettings: (() -> Void)?
    var onTogglePause: (() -> Void)?
    init(store: ClipboardStore, preferences: Preferences, monitor: ClipboardMonitor) {
        self.store = store; self.preferences = preferences; self.monitor = monitor
        super.init()
        panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "ClipHat"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false; panel.delegate = self
        panel.contentView = NSHostingView(rootView: ClipboardHistoryView(store: store, preferences: preferences, state: state,
            restore: { [weak self] in self?.restore($0) },
            showSettings: { [weak self] in self?.onShowSettings?() },
            togglePause: { [weak self] in self?.onTogglePause?() },
            togglePanelPin: { [weak self] in self?.preferences.panelPinned.toggle() },
            close: { [weak self] in self?.close() }))
        applyAppearance()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
    }
    func toggle() {
        resignDismissal?.cancel()
        panel.isVisible ? close() : show()
    }
    func updatePositionIfVisible() {
        guard panel.isVisible, let screen = targetScreen() else { return }
        applyLayout(on: screen)
    }
    func applyAppearance() { panel.appearance = preferences.appearance.nsAppearance }
    func keepVisibleWhenInactive() {
        guard preferences.panelPinned else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.preferences.panelPinned else { return }
            self.panel.orderFrontRegardless()
        }
    }
    func dismissForSettings() {
        previousApp = nil
        close()
    }
    func show() {
        resignDismissal?.cancel()
        previousApp = NSWorkspace.shared.frontmostApplication
        if previousApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier { previousApp = nil }
        state.query = ""; state.selected = store.items.first?.id; state.focusRequest = UUID()
        guard let screen = targetScreen() else {
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
            return
        }
        let finalFrame = Self.panelFrame(position: preferences.panelPosition, visibleFrame: screen.visibleFrame, largePreviews: preferences.largePreviews)
        panel.setFrame(Self.offscreenFrame(for: finalFrame, position: preferences.panelPosition), display: false)
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
        }
    }
    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }
    private func applyLayout(on screen: NSScreen) {
        let frame = Self.panelFrame(position: preferences.panelPosition, visibleFrame: screen.visibleFrame, largePreviews: preferences.largePreviews)
        panel.setFrame(frame, display: true)
    }
    static func panelFrame(position: PanelPosition, visibleFrame: NSRect, largePreviews: Bool = false) -> NSRect {
        let verticalWidth = min(350, max(300, visibleFrame.width * 0.19))
        let horizontalHeight = min(visibleFrame.height, min(255, max(225, visibleFrame.height * 0.25)) + (largePreviews ? 106 : 0))

        switch position {
        case .left:
            return NSRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: verticalWidth, height: visibleFrame.height)
        case .right:
            return NSRect(x: visibleFrame.maxX - verticalWidth, y: visibleFrame.minY,
                          width: verticalWidth, height: visibleFrame.height)
        case .top:
            return NSRect(x: visibleFrame.minX, y: visibleFrame.maxY - horizontalHeight,
                          width: visibleFrame.width, height: horizontalHeight)
        case .bottom:
            return NSRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: visibleFrame.width, height: horizontalHeight)
        }
    }
    private static func offscreenFrame(for frame: NSRect, position: PanelPosition) -> NSRect {
        switch position {
        case .left: return frame.offsetBy(dx: -frame.width, dy: 0)
        case .right: return frame.offsetBy(dx: frame.width, dy: 0)
        case .top: return frame.offsetBy(dx: 0, dy: frame.height)
        case .bottom: return frame.offsetBy(dx: 0, dy: -frame.height)
        }
    }
    func close() {
        resignDismissal?.cancel()
        guard panel.isVisible, !closing else { return }
        closing = true
        let endFrame = Self.offscreenFrame(for: panel.frame, position: preferences.panelPosition)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.closing = false
            self.previousApp?.activate(options: [])
            self.previousApp = nil
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        guard !preferences.panelPinned else { return }
        resignDismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.panel.isKeyWindow else { return }
            self.close()
        }
        resignDismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    private func restore(_ item: ClipboardItem) {
        guard !state.restoring else { return }; state.restoring = true
        if item.kind == .link, let value = item.text, let url = URL(string: value) {
            NSWorkspace.shared.open(url)
            state.restoring = false
            close()
            return
        }
        monitor.restore(item) { [weak self] success in
            guard let self else { return }; self.state.restoring = false
            if success { self.close() } else { self.store.error = "This item could not be restored to the clipboard." }
        }
    }
    private func handle(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            state.focusRequest = UUID(); return true
        }
        let items = store.items.filter { $0.matches(state.query) }
        switch event.keyCode {
        case 53: close(); return true
        case 125, 126:
            guard !items.isEmpty else { return true }
            let index = items.firstIndex { $0.id == state.selected } ?? (event.keyCode == 125 ? -1 : items.count)
            state.selected = items[min(items.count - 1, max(0, index + (event.keyCode == 125 ? 1 : -1)))].id
            return true
        case 123 where preferences.panelPosition.isHorizontal,
             124 where preferences.panelPosition.isHorizontal:
            guard !items.isEmpty else { return true }
            let index = items.firstIndex { $0.id == state.selected } ?? (event.keyCode == 124 ? -1 : items.count)
            state.selected = items[min(items.count - 1, max(0, index + (event.keyCode == 124 ? 1 : -1)))].id
            return true
        case 36, 76:
            if let item = items.first(where: { $0.id == state.selected }) { restore(item) }
            return true
        case 51 where event.modifierFlags.contains(.command):
            if let item = items.first(where: { $0.id == state.selected }) { store.delete(item) }; return true
        default: return false
        }
    }
    deinit {
        resignDismissal?.cancel()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}
