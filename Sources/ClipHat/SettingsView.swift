import AppKit
import SwiftUI
import ClipHatCore

final class SettingsNav: ObservableObject { @Published var tab = 0 }

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: ClipboardStore
    @ObservedObject var updates: UpdateChecker
    let clearAll: () -> Void
    let quit: () -> Void
    @StateObject private var nav = SettingsNav()
    private let tabs = ["General", "History", "Privacy", "About"]
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, title in
                    Button { nav.tab = index } label: {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(nav.tab == index ? Theme.accent : Theme.secondary)
                            .frame(maxWidth: .infinity).frame(height: 26)
                            .background(Capsule().fill(nav.tab == index ? Theme.card : Color.clear)
                                .shadow(color: .black.opacity(nav.tab == index ? 0.12 : 0), radius: 1.5, y: 0.5))
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    switch nav.tab {
                    case 0: general
                    case 1: history
                    case 2: privacy
                    default: about
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(18).frame(width: 490, height: 590)
        .background(Theme.page)
        .tint(Theme.accent)
        .foregroundStyle(Theme.text)
        .onAppear { preferences.refreshLogin() }
        .preferredColorScheme(preferences.appearance.colorScheme)
    }

    // MARK: Building blocks

    /// A titled card holding rows, separated by hairlines.
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary).padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 0) { content() }.card(padding: 0)
        }
    }
    /// One row: title and optional note on the left, the control on the right.
    private func row<Control: View>(_ title: String, _ note: String? = nil, last: Bool = false, @ViewBuilder _ control: () -> Control) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let note { Text(note).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                control()
            }.padding(.horizontal, 14).padding(.vertical, 10)
            if !last { Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 14) }
        }
    }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func toggleRow(_ title: String, _ note: String? = nil, last: Bool = false, isOn: Binding<Bool>) -> some View {
        row(title, note, last: last) { Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch) }
    }

    // MARK: Tabs

    @ViewBuilder private var general: some View {
        section("Startup") {
            toggleRow("Launch ClipHat at login", preferences.loginMessage.isEmpty ? nil : preferences.loginMessage, last: true,
                      isOn: Binding(get: { preferences.loginEnabled }, set: { preferences.setLogin($0) }))
        }
        section("Panel") {
            row("Keyboard shortcut", preferences.shortcutMessage.isEmpty ? nil : preferences.shortcutMessage) {
                Text("⌘ ⇧ V").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(Theme.control))
            }
            toggleRow("Large previews", "Show images and documents on 2× cards.", isOn: $preferences.largePreviews)
            row("Position", last: false) { PanelPositionPicker(selection: $preferences.panelPosition) }
            row("Appearance", last: true) { AppearancePicker(selection: $preferences.appearance) }
        }
        note("Select an item to copy it, then press ⌘V to paste.")
        Button("Quit ClipHat", action: quit).buttonStyle(TintButtonStyle(color: Theme.red))
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 6)
    }
    @ViewBuilder private var history: some View {
        section("Size") {
            row("Keep \(preferences.limit) items", "Oldest unpinned items go first. Pinned items are always kept.", last: true) {
                Stepper("", value: $preferences.limit, in: 10...5000, step: 10).labelsHidden()
            }
        }
        section("What to save") {
            toggleRow("Text", isOn: $preferences.storeText)
            toggleRow("Links", isOn: $preferences.storeLinks)
            toggleRow("Images", isOn: $preferences.storeImages)
            toggleRow("Documents and other files", last: true, isOn: $preferences.storeDocuments)
        }
        note("Up to 1 MB per text item, 10 MB per image and 20 MB per file. Unpinned images and files share 200 MB. Folders are not supported.")
        section("Clear history") {
            row("Unpinned items", "Keeps everything you pinned.") {
                Button("Clear") { store.clear(includePinned: false) }.buttonStyle(TintButtonStyle(color: Theme.accent))
            }
            row("Everything", "Removes pinned items too.", last: true) {
                Button("Clear All…", action: clearAll).buttonStyle(TintButtonStyle(color: Theme.red))
            }
        }
    }
    @ViewBuilder private var privacy: some View {
        section("Ignored apps") {
            let ids = preferences.ignoredApps.sorted()
            if ids.isEmpty {
                row("No ignored apps", "Clipboard activity from ignored apps is not saved.") { EmptyView() }
            }
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                row(appName(id), nil, last: false) {
                    Button { preferences.ignoredApps.remove(id) } label: { Image(systemName: "xmark") }
                        .buttonStyle(CircleButtonStyle(size: 22)).help("Stop ignoring \(appName(id))")
                        .accessibilityLabel("Stop ignoring \(appName(id))")
                }
            }
            row("Add an app", "Clipboard activity from it will not be saved.", last: true) {
                Button("Add…") { preferences.addIgnoredApps() }.buttonStyle(TintButtonStyle(color: Theme.accent))
            }
        }
        note("Everything stays on this Mac. Sensitive and transient clipboard markers are skipped. Apps may omit these markers; add any app you want excluded.")
    }
    @ViewBuilder private var about: some View {
        VStack(spacing: 10) {
            if let url = Bundle.main.url(forResource: "ClipHatIcon", withExtension: "png"), let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 84, height: 84)
            }
            Text("ClipHat").font(.system(size: 20, weight: .bold))
            Text("Never lose something you copied.").font(.system(size: 13, weight: .medium))
            Text("Version \(updates.currentVersion) · Part of GuruHat").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            if let update = updates.available {
                Link("Download ClipHat \(update.version) ›", destination: update.page)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        .padding(.vertical, 18).card(padding: 14)
        section("Free and private") {
            row("Free & open source", "MIT license.") { EmptyView() }
            row("No accounts, no cloud, no analytics", last: true) { EmptyView() }
        }
        section("Support") {
            row("Support ClipHat", "Donations keep GuruHat apps free. Thank you!", last: true) {
                // GuruHat's shared donation page (same as AI Meter and PC Mode).
                Link(destination: URL(string: "https://www.paypal.com/donate/?hosted_button_id=FHGYWD46722JS")!) {
                    Label("Donate", systemImage: "heart.fill")
                }.font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
            }
        }
    }
    private func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return ["com.1password.1password": "1Password",
                    "com.agilebits.onepassword7": "1Password 7",
                    "com.agilebits.onepassword-osx": "1Password (legacy)",
                    "com.bitwarden.desktop": "Bitwarden",
                    "com.dashlane.Dashlane": "Dashlane",
                    "com.enpass.Enpass": "Enpass"][id] ?? id
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

private struct AppearancePicker: View {
    @Binding var selection: AppAppearance

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppAppearance.allCases) { appearance in
                Button { selection = appearance } label: {
                    VStack(spacing: 3) {
                        AppearancePreview(appearance: appearance, selected: selection == appearance)
                        Text(appearance.title).font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == appearance ? Theme.accent : .secondary)
                .accessibilityLabel("Use \(appearance.title) appearance")
                .accessibilityAddTraits(selection == appearance ? .isSelected : [])
            }
        }
    }
}

private struct AppearancePreview: View {
    let appearance: AppAppearance
    let selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(background)
            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 2).fill(foreground.opacity(0.9)).frame(width: 24, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(foreground.opacity(0.55)).frame(width: 17, height: 3)
                RoundedRectangle(cornerRadius: 2).fill(foreground.opacity(0.55)).frame(width: 21, height: 3)
            }.padding(7)
        }
        .frame(width: 50, height: 30)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Theme.accent : Color.primary.opacity(0.14), lineWidth: selected ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(2)
    }

    private var background: Color {
        switch appearance {
        case .system: Color(nsColor: .windowBackgroundColor)
        case .light: .white
        case .dark: Color(white: 0.14)
        }
    }
    private var foreground: Color { appearance == .dark ? .white : .black }
}

private struct PanelPositionPicker: View {
    @Binding var selection: PanelPosition

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PanelPosition.allCases) { position in
                Button {
                    selection = position
                } label: {
                    PanelPositionIcon(position: position, selected: selection == position)
                }
                .buttonStyle(.plain)
                .help(position.tooltip)
                .accessibilityLabel(position.tooltip)
                .accessibilityAddTraits(selection == position ? .isSelected : [])
            }
        }
    }
}

private struct PanelPositionIcon: View {
    let position: PanelPosition
    let selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(selected ? Theme.accent : Color.secondary.opacity(0.55), lineWidth: 1)
                .frame(width: 27, height: 21)
            edge
        }
        .frame(width: 36, height: 30)
        .background(selected ? Theme.accent.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private var edge: some View {
        switch position {
        case .left:
            Rectangle().fill(selected ? Theme.accent : Color.secondary).frame(width: 5, height: 17).offset(x: -9)
        case .right:
            Rectangle().fill(selected ? Theme.accent : Color.secondary).frame(width: 5, height: 17).offset(x: 9)
        case .top:
            Rectangle().fill(selected ? Theme.accent : Color.secondary).frame(width: 23, height: 5).offset(y: -6)
        case .bottom:
            Rectangle().fill(selected ? Theme.accent : Color.secondary).frame(width: 23, height: 5).offset(y: 6)
        }
    }
}
