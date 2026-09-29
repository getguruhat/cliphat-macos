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
    @Environment(\.colorScheme) private var colorScheme
    let restore: (ClipboardItem) -> Void
    let showSettings: () -> Void
    let togglePause: () -> Void
    let togglePanelPin: () -> Void
    let close: () -> Void
    @FocusState private var searchFocused: Bool
    // In System mode, use the effective SwiftUI scheme so the panel background
    // stays in sync with its rows when macOS changes appearance.
    private var isDark: Bool { colorScheme == .dark }
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
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search clipboard…", text: $state.query)
                        .textFieldStyle(.plain).font(.system(size: 17)).focused($searchFocused)
                        .accessibilityLabel("Search clipboard")
                    if !state.query.isEmpty {
                        Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear search")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
            }
            HStack(spacing: 5) {
                Button {
                    state.searchVisible.toggle()
                    if state.searchVisible { state.focusRequest = UUID() }
                } label: { Image(systemName: "magnifyingglass").frame(width: 27, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(state.searchVisible ? Color.accentColor : .secondary)
                    .background(state.searchVisible ? Color.white.opacity(0.7) : .clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel("Search clipboard")
                ForEach(ContentFilter.allCases) { filter in
                    Button { state.filter = filter } label: {
                        filterIcon(for: filter).frame(width: 27, height: 24)
                    }
                        .buttonStyle(.plain)
                        .foregroundStyle(state.filter == filter ? Color.accentColor : .secondary)
                        .background(state.filter == filter ? Color.white.opacity(0.7) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .help(filter.rawValue.capitalized)
                        .accessibilityLabel("Show \(filter.rawValue)")
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
            Divider()
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red).padding(10)
            }
            if preferences.paused {
                Label("Clipboard history is paused", systemImage: "pause.circle.fill")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: state.query.isEmpty ? "clipboard" : "magnifyingglass").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text(state.query.isEmpty ? "Never lose something you copied." : "No matching items").font(.headline)
                    Text(state.query.isEmpty ? "Copy text, a link, or an image to get started." : "Try a different search.")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                history
            }
            Divider()
            HStack {
                Text("\(filtered.count) item\(filtered.count == 1 ? "" : "s")")
                Spacer()
                if state.restoring {
                    Text("Restoring…").foregroundStyle(.secondary)
                }
                Button { preferences.largePreviews.toggle() } label: {
                    Image(systemName: preferences.largePreviews ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(preferences.largePreviews ? Color.accentColor : .secondary)
                .help(preferences.largePreviews ? "Switch to compact cards" : "Switch to large previews (2× cards)")
                .accessibilityLabel("Large previews")
                .accessibilityValue(preferences.largePreviews ? "On" : "Off")
                toolbarButton(preferences.paused ? "play.fill" : "pause.fill",
                              preferences.paused ? "Resume Clipboard History" : "Pause Clipboard History",
                              action: togglePause)
                toolbarButton(preferences.panelPinned ? "pin.fill" : "pin",
                              preferences.panelPinned ? "Allow panel to auto-close" : "Keep panel open",
                              action: togglePanelPin)
                toolbarButton("gearshape", "Settings", action: showSettings)
            }.font(.system(size: 12)).padding(.horizontal, 16).padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDark ? Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.96) : Color(red: 0.84, green: 0.91, blue: 0.98).opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .preferredColorScheme(preferences.appearance.colorScheme)
        .onAppear { repairSelection() }
        .onChange(of: state.focusRequest) { _ in if state.searchVisible { searchFocused = true } }
        .onChange(of: state.query) { _ in state.selected = filtered.first?.id }
        .onChange(of: state.filter) { _ in state.selected = filtered.first?.id }
        .onChange(of: store.items) { _ in repairSelection() }
    }
    private func toolbarButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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
                                    Text(dayLabel(column.items[0].copiedAt)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                } else {
                                    Text(" ").font(.caption)
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
                                Text(dayLabel(item.copiedAt)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
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
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
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
                    .font(.system(size: 11)).foregroundStyle(.secondary)
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
                                    .font(.system(size: 36)).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        if item.kind == .image {
                            Text("Image - \(images.metadata.replacingOccurrences(of: " · ", with: " - "))")
                                .font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                        } else {
                            Text("\(item.filename ?? "File") - \(images.metadata.split(separator: "·").last?.trimmingCharacters(in: .whitespaces) ?? "File")")
                                .font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
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
                                .foregroundStyle(item.kind == .link ? Color.purple : Color.blue)
                                .frame(width: 44, height: 44)
                                .background((isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.72)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.kind == .image || item.kind == .document || item.kind == .audio ? (item.filename ?? "File") : (item.text ?? "Image"))
                                .font(.system(size: 14, weight: .semibold)).lineLimit(2)
                            Text(images.metadata).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            Text(sourceName).help(sourcePath)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
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
                                .foregroundStyle(item.kind == .link ? Color.purple : Color.blue)
                                .frame(width: 44, height: 44)
                                .background((isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.72)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.kind == .image || item.kind == .document || item.kind == .audio ? (item.filename ?? "File") : (item.text ?? "Image"))
                                .font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(images.metadata).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            Text(sourceName).help(sourcePath)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if !largePreview { Spacer(minLength: 0) }
        }
        .padding(12)
        .frame(height: largePreview ? (horizontal ? 202 : 234) : (horizontal ? 96 : 112))
        .background(isDark ? Color(red: 0.20, green: 0.22, blue: 0.27).opacity(0.96) : Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.accentColor : (isDark ? Color.white.opacity(0.16) : Color.white.opacity(0.10)), lineWidth: selected ? 2 : 1)
        }
        .help(sourcePath)
    }

    private var deleteButton: some View {
        Button(action: delete) {
            Image(systemName: "xmark")
                .font(.system(size: 5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 10, height: 10)
                .background(Color.red, in: Circle())
        }
        .buttonStyle(.plain)
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

    private var sourcePath: String {
        if (item.kind == .document || item.kind == .audio || item.kind == .image), let path = item.text, path.hasPrefix("/"), !path.isEmpty { return path }
        if let source = item.source, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) { return url.path }
        return sourceName
    }
}
