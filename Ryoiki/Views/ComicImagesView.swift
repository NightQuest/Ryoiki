import SwiftUI
import SwiftData
import CoreGraphics
import Observation

struct ComicImagesView: View {
    let comic: Comic

    @State private var selectionManager = SelectionManager()
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
                    ContentUnavailableView("No downloaded images",
                                           systemImage: "photo",
                                           description: Text("Use Update to download images first."))
                    .padding()
                } else {
                    ImagesGrid(
                        downloadedPages: downloadedPages,
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
            Button("Select All") { selectionManager.setSelection(Set(downloadedPages.map { $0.id })) }
                .keyboardShortcut("A", modifiers: .command)
                .disabled(downloadedPages.isEmpty || selectionManager.selection.count == downloadedPages.count)
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
