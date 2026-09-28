import AppKit
import SwiftUI
import ClipHatCore

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: ClipboardStore
    let clearAll: () -> Void
    let quit: () -> Void
    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Launch ClipHat at login", isOn: Binding(get: { preferences.loginEnabled }, set: { preferences.setLogin($0) }))
                if !preferences.loginMessage.isEmpty { Text(preferences.loginMessage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                LabeledContent("Keyboard shortcut", value: "⌘ ⇧ V")
                Toggle("Large image and document previews (2× cards)", isOn: $preferences.largePreviews)
                if !preferences.shortcutMessage.isEmpty { Text(preferences.shortcutMessage).font(.caption).foregroundStyle(.red) }
                HStack(spacing: 12) {
                    Text("Panel position")
                    Spacer()
                    PanelPositionPicker(selection: $preferences.panelPosition)
                }
                HStack(spacing: 12) {
                    Text("Appearance")
                    Spacer()
                    AppearancePicker(selection: $preferences.appearance)
                }
                Text("Select an item to copy it, then press ⌘V to paste.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Button("Quit ClipHat", role: .destructive, action: quit)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).tabItem { Label("General", systemImage: "gearshape") }
            VStack(alignment: .leading, spacing: 16) {
                Stepper(value: $preferences.limit, in: 10...5000, step: 10) {
                    Text("Keep \(preferences.limit) clipboard items")
                }
                Text("Oldest unpinned items are removed first. Pinned items are always kept.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Store").font(.headline)
                    Toggle("Text", isOn: $preferences.storeText)
                    Toggle("Links", isOn: $preferences.storeLinks)
                    Toggle("Images", isOn: $preferences.storeImages)
                    Toggle("Documents and other files", isOn: $preferences.storeDocuments)
                }
                Text("Up to 1 MB per text item, 10 MB per image, and 20 MB per file. Unpinned images and files share 200 MB. Folders are not supported.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("Clear History").font(.headline)
                HStack {
                    Button("Clear Unpinned History") { store.clear(includePinned: false) }
                    Button("Clear All History…", role: .destructive, action: clearAll)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).tabItem { Label("History", systemImage: "clock") }
            VStack(alignment: .leading, spacing: 12) {
                Text("Ignored Apps").font(.headline)
                Text("Clipboard activity from these apps is not saved.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                List {
                    ForEach(preferences.ignoredApps.sorted(), id: \.self) { id in
                        HStack {
                            Text(appName(id)).lineLimit(1).help(id)
                            Spacer()
                            Button { preferences.ignoredApps.remove(id) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).accessibilityLabel("Stop ignoring \(appName(id))")
                        }
                    }
                }.frame(height: 150)
                Button("Add Applications…") { preferences.addIgnoredApps() }
                Text("Everything stays on this Mac. Sensitive and transient clipboard markers are skipped. Apps may omit these markers; add any app you want excluded.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.tabItem { Label("Privacy", systemImage: "hand.raised") }
            VStack(spacing: 12) {
                Image(systemName: "clipboard").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("ClipHat").font(.title.bold())
                Text("Never lose something you copied.")
                Text("Version 1.0.0 · Part of GuruHat").foregroundStyle(.secondary)
                Text("Free & Open Source · MIT License").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("No accounts. No cloud. No analytics.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label("About", systemImage: "info.circle") }
        }.padding(20).frame(width: 490, height: 390)
        .onAppear { preferences.refreshLogin() }
        .preferredColorScheme(preferences.appearance.colorScheme)
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
                .foregroundStyle(selection == appearance ? Color.accentColor : .secondary)
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
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: selected ? 2 : 1))
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
                .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.55), lineWidth: 1)
                .frame(width: 27, height: 21)
            edge
        }
        .frame(width: 36, height: 30)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private var edge: some View {
        switch position {
        case .left:
            Rectangle().fill(selected ? Color.accentColor : Color.secondary).frame(width: 5, height: 17).offset(x: -9)
        case .right:
            Rectangle().fill(selected ? Color.accentColor : Color.secondary).frame(width: 5, height: 17).offset(x: 9)
        case .top:
            Rectangle().fill(selected ? Color.accentColor : Color.secondary).frame(width: 23, height: 5).offset(y: -6)
        case .bottom:
            Rectangle().fill(selected ? Color.accentColor : Color.secondary).frame(width: 23, height: 5).offset(y: 6)
        }
    }
}
