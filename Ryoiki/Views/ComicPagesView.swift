import SwiftUI
import SwiftData
import CoreGraphics
import Observation

struct ComicPagesView: View {
    let comic: Comic

    @State private var model = ComicPagesSelectionModel()
    @State private var pendingLayoutUpdate: Task<Void, Never>?

    private var downloadedPages: [ComicPage] {
        comic.pages
            .sorted { $0.index < $1.index }
            .filter { page in
                guard let url = page.downloadedFileURL else { return false }
                return FileManager.default.fileExists(atPath: url.path)
            }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if downloadedPages.isEmpty {
                    ContentUnavailableView("No downloaded pages",
                                           systemImage: "photo",
                                           description: Text("Use Update to download images first."))
                    .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: adaptiveColumns, spacing: Layout.gridSpacing) {
                            ForEach(downloadedPages, id: \.id) { page in
                                PageTile(page: page, isSelected: model.selection.contains(page.id))
                                    .contentShape(Rectangle())
                                    // Command+Shift-click: union range with current selection
                                    .highPriorityGesture(
                                        TapGesture().modifiers([.command, .shift])
                                            .onEnded { model.unionWithRange(to: page.id) }
                                    )
                                    // Command-click: toggle single item
                                    .highPriorityGesture(
                                        TapGesture().modifiers(.command)
                                            .onEnded {
                                                model.toggleSelection(page.id)
                                            }
                                    )
                                    // Shift-click: replace selection with range from anchor to clicked
                                    .highPriorityGesture(
                                        TapGesture().modifiers(.shift)
                                            .onEnded { model.replaceWithRange(to: page.id) }
                                    )
                                    // Plain click: replace selection with this item
                                    .onTapGesture {
                                        model.replaceSelection(with: page.id)
                                    }
                                    .anchorPreference(key: TileFramesPreferenceKey.self, value: .bounds) { anchor in
                                        [page.id: anchor]
                                    }
                                    .contextMenu {
                                        Button(model.selection.contains(page.id) ? "Deselect" : "Select") {
                                            model.toggleSelection(page.id)
                                        }
                                    }
                            }
                        }
                        .padding(Layout.gridPadding)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0).modifiers(.command)
                                .onChanged { value in
                                    if model.selectionRect == nil {
                                        model.beginDrag(at: value.startLocation, mode: .toggle)
                                    }
                                    model.updateDrag(to: value.location, mode: .toggle)
                                }
                                .onEnded { value in
                                    model.endDrag(at: value.location)
                                }
                        )
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0).modifiers(.shift)
                                .onChanged { value in
                                    if model.selectionRect == nil {
                                        model.beginDrag(at: value.startLocation, mode: .union)
                                    }
                                    model.updateDrag(to: value.location, mode: .union)
                                }
                                .onEnded { value in
                                    model.endDrag(at: value.location)
                                }
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if model.selectionRect == nil {
                                        model.beginDrag(at: value.startLocation, mode: .replace)
                                    }
                                    model.updateDrag(to: value.location, mode: .replace)
                                }
                                .onEnded { value in
                                    model.endDrag(at: value.location)
                                }
                        )
                        .overlay(alignment: .topLeading) {
                            if let rect = model.selectionRect {
                                ZStack {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)
                                    Rectangle()
                                        .stroke(Color.accentColor, lineWidth: 1)
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .backgroundPreferenceValue(TileFramesPreferenceKey.self) { anchors in
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        let frames = resolveFrames(anchors, proxy: proxy)
                                        let origin = proxy.frame(in: .global).origin
                                        let ids = downloadedPages.map { $0.id }
                                        scheduleLayoutUpdate(frames: frames, origin: origin, orderedIDs: ids)
                                    }
                                    .onChange(of: anchors) { _, _ in
                                        let frames = resolveFrames(anchors, proxy: proxy)
                                        let origin = proxy.frame(in: .global).origin
                                        let ids = downloadedPages.map { $0.id }
                                        scheduleLayoutUpdate(frames: frames, origin: origin, orderedIDs: ids)
                                    }
                            }
                        }
                    }
                    .toolbar { selectionToolbar }
                }
            }
        }
        .navigationTitle("Pages: \(comic.name)")
    }

    private func scheduleLayoutUpdate(frames: [UUID: CGRect], origin: CGPoint, orderedIDs: [UUID]) {
        pendingLayoutUpdate?.cancel()
        pendingLayoutUpdate = Task { @MainActor in
            // Coalesce multiple updates in the same frame
            try? await Task.sleep(for: .milliseconds(1))
            if Task.isCancelled { return }
            model.updateItemFrames(frames)
            model.updateGridOrigin(origin)
            model.updateOrderedIDs(orderedIDs)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Select All") { model.selection = Set(downloadedPages.map { $0.id }) }
                .disabled(downloadedPages.isEmpty || model.selection.count == downloadedPages.count)
            Button("Clear Selection") { model.selection.removeAll() }
                .disabled(model.selection.isEmpty)
            Text("\(model.selection.count) selected")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Layout

    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140, maximum: 260), spacing: Layout.gridSpacing, alignment: .top)]
    }

    private func resolveFrames(_ anchors: [UUID: Anchor<CGRect>], proxy: GeometryProxy) -> [UUID: CGRect] {
        let origin = proxy.frame(in: .global).origin
        var dict: [UUID: CGRect] = [:]
        dict.reserveCapacity(anchors.count)
        for (id, anchor) in anchors {
            let local = proxy[anchor]
            dict[id] = local.offsetBy(dx: origin.x, dy: origin.y)
        }
        return dict
    }
}

private struct TileFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct PageTile: View {
    let page: ComicPage
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .fill(.quinary.opacity(0.4))
                if let url = page.downloadedFileURL {
                    ThumbnailImage(url: url, maxPixel: 512)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(page.title.isEmpty ? "#\(page.index)" : page.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(URL(string: page.pageURL)?.host ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}
