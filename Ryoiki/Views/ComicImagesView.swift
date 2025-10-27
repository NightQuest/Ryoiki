import SwiftUI
import SwiftData
import CoreGraphics
import Observation

struct ComicImagesView: View {
    let comic: Comic

    @State private var selectionManager = SelectionManager()
    @State private var pendingLayoutUpdate: Task<Void, Never>?

    private var downloadedImages: [DownloadedImageItem] {
        comic.pages
            .sorted { $0.index < $1.index }
            .flatMap { page in
                page.images
                    .sorted { $0.index < $1.index }
                    .compactMap { image -> DownloadedImageItem? in
                        guard let url = image.fileURL else { return nil }
                        // Ensure the file is a regular file, non-empty, and not being modified right now
                        let rv = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                        guard rv?.isRegularFile != false else { return nil }
                        guard (rv?.fileSize ?? 0) > 0 else { return nil }
                        if let mdate = rv?.contentModificationDate, Date().timeIntervalSince(mdate) < 0.2 {
                            // Skip files modified in the last 200ms to avoid racing a writer
                            return nil
                        }
                        return DownloadedImageItem(id: image.id, pageID: page.id, imageID: image.id, fileURL: url)
                    }
            }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if downloadedImages.isEmpty {
                    ContentUnavailableView("No downloaded images",
                                           systemImage: "photo",
                                           description: Text("Use Update to download images first."))
                    .padding()
                } else {
                    ImagesGrid(
                        downloadedImages: downloadedImages,
                        comic: comic,
                        selectionManager: $selectionManager,
                        onLayoutUpdate: { frames, origin, ids in
                            scheduleLayoutUpdate(frames: frames, origin: origin, orderedIDs: ids)
                        }
                    )
                    .toolbar { selectionToolbar }
                    .onAppear {
                        selectionManager
                            .onSelectionChange { _ in }
                            .onBeginDrag { _, _ in }
                            .onUpdateDrag { _, _ in }
                            .onEndDrag { _ in }
                    }
                }
            }
        }
        .navigationTitle("Images: \(comic.name)")
    }

    private func scheduleLayoutUpdate(frames: [UUID: CGRect], origin: CGPoint, orderedIDs: [UUID]) {
        pendingLayoutUpdate?.cancel()
        pendingLayoutUpdate = Task { @MainActor in
            // Coalesce multiple updates in the same frame
            try? await Task.sleep(for: .milliseconds(1))
            if Task.isCancelled { return }
            selectionManager.updateItemFrames(frames)
            selectionManager.updateGridOrigin(origin)
            selectionManager.updateOrderedIDs(orderedIDs)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Select All") { selectionManager.setSelection(Set(downloadedImages.map { $0.id })) }
                .keyboardShortcut("A", modifiers: .command)
                .disabled(downloadedImages.isEmpty || selectionManager.selection.count == downloadedImages.count)
            Button("Clear Selection") { selectionManager.clearSelection() }
                .keyboardShortcut("D", modifiers: .command)
                .disabled(selectionManager.selection.isEmpty)
            Text("\(selectionManager.selection.count) selected")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Layout

    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140, maximum: 260), spacing: Layout.gridSpacing, alignment: .top)]
    }
}
