import SwiftUI
import SwiftData

struct ComicGrid: View {
    let comics: [Comic]
    @Binding var selectedComic: Comic?
    @Binding var isInspectorAnimating: Bool
    let itemsPerRowPreference: Int
    let showBadges: Bool
    let fetchingComicIDs: Set<UUID>
    let updatingComicIDs: Set<UUID>
    let frozenBadgeCounts: [UUID: Int]

    let onEdit: ((Comic) -> Void)?
    let onFetch: ((Comic) -> Void)?
    let onUpdate: ((Comic) -> Void)?
    let onOpenPages: ((Comic) -> Void)?

    @Environment(\.modelContext) private var modelContext

    @State private var showDeleteAlert: Bool = false
    @State private var comicPendingDelete: Comic?

    var body: some View {
        ScrollView {
            let columns: [GridItem] = computedColumns(itemsPerRowPreference: itemsPerRowPreference)

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
                              overridePageCount: frozenBadgeCounts[comic.id])
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedComic = comic
                    }
                },
                contextMenu: { comic, _ in
                    Group {
                        Button { onOpenPages?(comic) } label: { Label("Pages", systemImage: "square.grid.3x3") }
                        Button { onEdit?(comic) } label: { Label("Edit", systemImage: "pencil") }
                        Divider()
                        Button { onFetch?(comic) } label: { Label("Fetch", systemImage: "tray.and.arrow.down") }
                        Button { onUpdate?(comic) } label: { Label("Update", systemImage: "square.and.arrow.down") }
                        Divider()
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
            Text("This will remove the comic and all of its downloaded pages. This action cannot be undone.")
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
