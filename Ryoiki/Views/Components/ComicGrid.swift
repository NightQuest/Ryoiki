import SwiftUI
import SwiftData

struct ComicGrid: View {
    let comics: [Comic]
    @Binding var selectedComic: Comic?
    let itemsPerRowPreference: Int
    let fetchingComicIDs: Set<UUID>
    let updatingComicIDs: Set<UUID>

    let onEdit: ((Comic) -> Void)?
    let onFetch: ((Comic) -> Void)?
    let onUpdate: ((Comic) -> Void)?
    let onOpenPages: ((Comic) -> Void)?
    let onRead: ((Comic) -> Void)?

    @Environment(\.modelContext) private var modelContext

    @State private var showDeleteAlert: Bool = false
    @State private var comicPendingDelete: Comic?

    @State private var showCleanupAlert: Bool = false
    @State private var comicPendingCleanup: Comic?

    var body: some View {
        ScrollView {
            let columns: [GridItem] = computedColumns(itemsPerRowPreference: itemsPerRowPreference)

            ZStack {
                EntityGrid(
                    items: comics,
                    selectionManager: .constant(SelectionManager()),
                    onLayoutUpdate: { _, _, _ in },
                    columns: columns,
                    tile: { comic, _ in
                        ComicTile(comic: comic,
                                  isSelected: selectedComic == comic,
                                  isFetching: fetchingComicIDs.contains(comic.id),
                                  isUpdating: updatingComicIDs.contains(comic.id),
                                  overridePageCount: comic.undownloadedPageCount())
                        .contentShape(Rectangle())
                        .onTapGesture { selectedComic = comic }
                    },
                    contextMenu: { comic, _ in
                        Group {
                            Button { onRead?(comic) } label: { Label("Read", systemImage: "book") }
                            Button { onOpenPages?(comic) } label: { Label("Images", systemImage: "square.grid.3x3") }
                            Button { onEdit?(comic) } label: { Label("Edit", systemImage: "pencil") }
                            Divider()
                            Button { onFetch?(comic) } label: { Label("Fetch", systemImage: "tray.and.arrow.down") }
                            Button { onUpdate?(comic) } label: { Label("Update", systemImage: "square.and.arrow.down") }
                            Divider()
                            Button(role: .destructive) {
                                comicPendingCleanup = comic
                                showCleanupAlert = true
                            } label: { Label("Clear Data", systemImage: "trash.slash") }
                            Button(role: .destructive) {
                                comicPendingDelete = comic
                                showDeleteAlert = true
                            } label: { Label("Delete Comic…", systemImage: "trash") }
                        }
                    }
                )
                .transaction { $0.animation = nil }
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedComic = nil
                        }
                )
            }
        }
        .alert("Delete \"\(comicPendingDelete?.name ?? "Comic")\"?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let comic = comicPendingDelete {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let cm = ComicManager()
                    cm.deleteDownloadFolder(for: comic, in: docs)
                    modelContext.delete(comic)
                    try? modelContext.save()
                    if selectedComic == comic { selectedComic = nil }
                }
                comicPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                comicPendingDelete = nil
            }
        } message: {
            Text("This will remove the comic and all of its downloaded images. This action cannot be undone.")
        }
        .alert("Clear Data for \"\(comicPendingCleanup?.name ?? "Comic")\"?", isPresented: $showCleanupAlert) {
            Button("Clear", role: .destructive) {
                if let comic = comicPendingCleanup {
                    // Delete downloaded folder
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let cm = ComicManager()
                    cm.deleteDownloadFolder(for: comic, in: docs)

                    // Delete fetched pages associated with this comic from the model context
                    for page in comic.pages {
                        modelContext.delete(page)
                    }

                    try? modelContext.save()
                }
                comicPendingCleanup = nil
            }
            Button("Cancel", role: .cancel) {
                comicPendingCleanup = nil
            }
        } message: {
            Text("This will delete all downloaded images for this comic and remove its download folder. " +
                 "The comic entry will remain. This action cannot be undone.")
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                selectedComic = nil
            }
        )
    }

    private func computedColumns(itemsPerRowPreference: Int, minTileWidth: CGFloat = 160) -> [GridItem] {
        let spacing = Layout.gridSpacing
        if itemsPerRowPreference > 0 {
            let count = max(1, itemsPerRowPreference)
            // Fixed number of columns; tiles will shrink/grow to fit while maintaining their internal aspect ratios
            return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
        } else {
            // Fallback to adaptive when no preference is set
            return [GridItem(.adaptive(minimum: minTileWidth, maximum: 260), spacing: spacing, alignment: .top)]
        }
    }
}
