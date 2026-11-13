import AppKit
import SwiftUI
import ClipHatCore

final class PickerState: ObservableObject {
    @Published var query = ""
    @Published var filter: ContentFilter = .all
    @Published var searchVisible = false
    @Published var selected: Int64?
    @Published var focusRequest = UUID()
    @Published var restoring = false
}

enum ContentFilter: String, CaseIterable, Identifiable {
    case all, text, links, media, documents, audio
    var id: String { rawValue }
    var symbol: String {
        switch self { case .all: "square.grid.2x2"; case .text: "textformat"; case .links: "link"; case .media: "photo"; case .documents: "doc.text"; case .audio: "music.note" }
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var preferences: Preferences
    @ObservedObject var state: PickerState
    let restore: (ClipboardItem) -> Void
    let showSettings: () -> Void
    let togglePause: () -> Void
    let togglePanelPin: () -> Void
    let close: () -> Void
    @FocusState private var searchFocused: Bool
    private var filtered: [ClipboardItem] {
        store.items.filter { item in
            item.matches(state.query) && (state.filter == .all ||
                (state.filter == .text && item.kind == .text) ||
                (state.filter == .links && item.kind == .link) ||
                (state.filter == .media && item.kind == .image) ||
                (state.filter == .documents && item.kind == .document) ||
                (state.filter == .audio && item.kind == .audio))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            if state.searchVisible {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField("Search clipboard…", text: $state.query)
                        .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Theme.text).focused($searchFocused)
                        .accessibilityLabel("Search clipboard")
                    if !state.query.isEmpty {
                        Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Theme.secondary).help("Clear search")
                    }
                }
                .padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().strokeBorder(Theme.stroke))
                .padding(.horizontal, 12).padding(.top, 12)
            }
            HStack(spacing: 2) {
                filterButton(symbol: "magnifyingglass", active: state.searchVisible, help: "Search clipboard") {
                    state.searchVisible.toggle()
                    if state.searchVisible { state.focusRequest = UUID() }
                }
                ForEach(ContentFilter.allCases) { filter in
                    filterButton(icon: filterIcon(for: filter), active: state.filter == filter,
                                 help: filter.rawValue.capitalized) { state.filter = filter }
                        .accessibilityLabel("Show \(filter.rawValue)")
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 2)
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(Theme.red).padding(10)
            }
            if preferences.paused {
                Label("Clipboard history is paused", systemImage: "pause.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.orange).padding(8)
            }
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: state.query.isEmpty ? "clipboard.fill" : "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.accent.opacity(0.13)))
                    Text(state.query.isEmpty ? "Never lose something you copied." : "No matching items")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(state.query.isEmpty ? "Copy text, a link, or an image to get started." : "Try a different search.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                history
            }
            HStack(spacing: 6) {
                Text("\(filtered.count) item\(filtered.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(Theme.card))
                Spacer()
                if state.restoring {
                    Text("Restoring…").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                toolbarButton(preferences.largePreviews ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                              preferences.largePreviews ? "Switch to compact cards" : "Switch to large previews (2× cards)",
                              active: preferences.largePreviews) { preferences.largePreviews.toggle() }
                toolbarButton(preferences.paused ? "play.fill" : "pause.fill",
                              preferences.paused ? "Resume Clipboard History" : "Pause Clipboard History",
                              active: preferences.paused, action: togglePause)
                toolbarButton(preferences.panelPinned ? "pin.fill" : "pin",
                              preferences.panelPinned ? "Allow panel to auto-close" : "Keep panel open",
                              active: preferences.panelPinned, action: togglePanelPin)
                toolbarButton("gearshape", "Settings", action: showSettings)
            }.padding(.horizontal, 12).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque, in the panel's rounded shape, like ServerHat's menu.
        .background(Theme.page)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke) }
        .preferredColorScheme(preferences.appearance.colorScheme)
        .onAppear { repairSelection() }
        .onChange(of: state.focusRequest) { _ in if state.searchVisible { searchFocused = true } }
        .onChange(of: state.query) { _ in state.selected = filtered.first?.id }
        .onChange(of: state.filter) { _ in state.selected = filtered.first?.id }
        .onChange(of: store.items) { _ in repairSelection() }
    }
    private func toolbarButton(_ symbol: String, _ help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(CircleButtonStyle(size: 26,
                                           fill: active ? Theme.accent.opacity(0.14) : Theme.card,
                                           foreground: active ? Theme.accent : Theme.secondary))
            .help(help)
            .accessibilityLabel(help)
    }
    private func filterButton(symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        filterButton(icon: Image(systemName: symbol), active: active, help: help, action: action)
    }
    private func filterButton<Icon: View>(icon: Icon, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Theme.accent : Theme.secondary)
                .frame(width: 30, height: 24)
                .background(Capsule().fill(active ? Theme.card : Color.clear)
                    .shadow(color: .black.opacity(active ? 0.12 : 0), radius: 1.5, y: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
    @ViewBuilder private func filterIcon(for filter: ContentFilter) -> some View {
        if filter == .audio,
           let url = Bundle.main.url(forResource: "MusicFilterIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().padding(3)
        } else {
            Image(systemName: filter.symbol)
        }
    }
    @ViewBuilder private var history: some View {
        ScrollViewReader { proxy in
            if preferences.panelPosition.isHorizontal {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 8) {
                        ForEach(Array(horizontalColumns.enumerated()), id: \.element.id) { index, column in
                            VStack(alignment: .leading, spacing: 5) {
                                if index == 0 || !Calendar.current.isDate(column.items[0].copiedAt, inSameDayAs: horizontalColumns[index - 1].items[0].copiedAt) {
                                    Text(dayLabel(column.items[0].copiedAt)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                                } else {
                                    Text(" ").font(.system(size: 12))
                                }
                                VStack(spacing: 10) {
                                    ForEach(column.items) { item in
                                        row(item, horizontal: true).frame(width: 260).id(item.id)
                                    }
                                }
                            }
                        }
                    }.padding(10)
                }
                .onChange(of: state.selected) { id in if let id { proxy.scrollTo(id) } }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                            if index == 0 || !Calendar.current.isDate(item.copiedAt, inSameDayAs: filtered[index - 1].copiedAt) {
                                Text(dayLabel(item.copiedAt)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                                    .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 0)
                            }
                            row(item, horizontal: false).id(item.id)
                        }
                    }.padding(10)
                }
                .onChange(of: state.selected) { id in if let id { proxy.scrollTo(id) } }
            }
        }
    }
    private struct HistoryColumn: Identifiable {
        var items: [ClipboardItem]
        var id: Int64 { items[0].id }
    }
    private var horizontalColumns: [HistoryColumn] {
        var columns: [HistoryColumn] = []
        for item in filtered {
            let small = item.kind == .text || item.kind == .link
            if preferences.largePreviews, small, let last = columns.last,
               last.items.count == 1,
               last.items[0].kind == .text || last.items[0].kind == .link,
               Calendar.current.isDate(item.copiedAt, inSameDayAs: last.items[0].copiedAt) {
                columns[columns.count - 1].items.append(item)
            } else {
                columns.append(HistoryColumn(items: [item]))
            }
        }
        return columns
    }
    private func row(_ item: ClipboardItem, horizontal: Bool) -> some View {
        ClipboardRowView(item: item, selected: state.selected == item.id, store: store,
            horizontal: horizontal, largePreview: preferences.largePreviews && (item.kind == .image || item.kind == .document || item.kind == .audio),
            select: { state.selected = item.id; restore(item) },
            pin: { store.pin(item, limit: preferences.limit) }, delete: { store.delete(item) })
    }
    private func repairSelection() {
        if !filtered.contains(where: { $0.id == state.selected }) { state.selected = filtered.first?.id }
    }
    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

final class RowImages: ObservableObject {
    @Published var thumbnail: NSImage?
    @Published var sourceIcon: NSImage?
    @Published var metadata = ""
}

struct ClipboardRowView: View {
    let item: ClipboardItem
    let selected: Bool
    @ObservedObject var store: ClipboardStore
    let horizontal: Bool
    let largePreview: Bool
    let select: () -> Void
    let pin: () -> Void
    let delete: () -> Void
    @StateObject private var images = RowImages()
    var body: some View {
        card
        .contextMenu {
            Button("Copy to Clipboard", action: select)
            Button(item.pinned ? "Unpin" : "Pin", action: pin)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .onDrag { store.dragProvider(for: item) }
        .onAppear { loadImages() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                deleteButton
                Spacer()
                Text(item.copiedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 0)
            .frame(height: horizontal ? 18 : nil, alignment: .center)
            .offset(y: horizontal ? 4 : 0)
            if largePreview {
                Button(action: select) {
                    VStack(alignment: .leading, spacing: 5) {
                        Group {
                            if let thumbnail = images.thumbnail {
                                Image(nsImage: thumbnail).resizable().scaledToFit()
                            } else {
                                Image(systemName: item.kind == .document ? "doc.text" : (item.kind == .audio ? "music.note" : "photo"))
                                    .font(.system(size: 36)).foregroundStyle(Theme.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        if item.kind == .image {
                            Text("Image - \(images.metadata.replacingOccurrences(of: " · ", with: " - "))")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.85)
                        } else {
                            Text("\(item.filename ?? "File") - \(images.metadata.split(separator: "·").last?.trimmingCharacters(in: .whitespaces) ?? "File")")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.85)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if horizontal {
                Button(action: select) {
                    HStack(alignment: .top, spacing: 11) {
                        if (item.kind == .image || item.kind == .document || item.kind == .audio), let thumbnail = images.thumbnail {
                            Image(nsImage: thumbnail).resizable().scaledToFill()
                                .frame(width: 82, height: 62).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            Image(systemName: item.kind == .link ? "link" : (item.kind == .document ? "doc.text" : (item.kind == .audio ? "music.note" : "textformat")))
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(tint)
                                .frame(width: 40, height: 40)
                                .background(tint.opacity(0.13), in: Circle())
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.kind == .image || item.kind == .document || item.kind == .audio ? (item.filename ?? "File") : (item.text ?? "Image"))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                            Text(images.metadata).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                            Text(sourceName).help(hoverText)
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            } else {
                Button(action: select) {
                    HStack(alignment: .top, spacing: 11) {
                        if (item.kind == .image || item.kind == .document || item.kind == .audio), let thumbnail = images.thumbnail {
                            Image(nsImage: thumbnail).resizable().scaledToFill()
                                .frame(width: 82, height: 62).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            Image(systemName: item.kind == .link ? "link" : (item.kind == .document ? "doc.text" : (item.kind == .audio ? "music.note" : "textformat")))
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(tint)
                                .frame(width: 40, height: 40)
                                .background(tint.opacity(0.13), in: Circle())
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.kind == .image || item.kind == .document || item.kind == .audio ? (item.filename ?? "File") : (item.text ?? "Image"))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(images.metadata).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                            Text(sourceName).help(hoverText)
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if !largePreview { Spacer(minLength: 0) }
        }
        .padding(12)
        .frame(height: largePreview ? (horizontal ? 202 : 234) : (horizontal ? 96 : 112))
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 2 : 1)
        }
        .help(hoverText)
    }

    private var tint: Color { item.kind == .link ? Theme.green : (item.kind == .text ? Theme.accent : Theme.orange) }

    private var deleteButton: some View {
        Button(action: delete) { Image(systemName: "xmark") }
            .buttonStyle(CircleButtonStyle(size: 18))
            .help("Delete this item")
            .accessibilityLabel("Delete this item")
    }

    private func loadImages() {
        if item.kind == .image || item.kind == .document || item.kind == .audio { store.thumbnail(for: item) { images.thumbnail = $0 } }
        store.metadata(for: item) { images.metadata = $0 }
        if let id = item.source, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            images.sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    private var sourceName: String {
        guard let source = item.source,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) else { return "Unknown source" }
        return FileManager.default.displayName(atPath: url.path)
    }

    private var hoverText: String {
        guard item.kind == .text || item.kind == .link, let text = item.text, !text.isEmpty else { return sourcePath }
        return text.count > 2000 ? String(text.prefix(2000)) + "…" : text
    }

    private var sourcePath: String {
        if (item.kind == .document || item.kind == .audio || item.kind == .image), let path = item.text, path.hasPrefix("/"), !path.isEmpty { return path }
        if let source = item.source, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) { return url.path }
        return sourceName
    }
}
