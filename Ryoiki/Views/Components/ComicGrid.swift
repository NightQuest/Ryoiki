import SwiftUI
import SwiftData

struct ComicGrid: View {
    let comics: [Comic]
    @Binding var selectedComic: Comic?
    @Binding var isInspectorAnimating: Bool
    let itemsPerRowPreference: Int

    let onEdit: ((Comic) -> Void)?
    let onFetch: ((Comic) -> Void)?
    let onUpdate: ((Comic) -> Void)?
    let onOpenPages: ((Comic) -> Void)?

    @Environment(\.modelContext) private var modelContext

    @State private var frozenWidth: CGFloat?
    @State private var showDeleteAlert: Bool = false
    @State private var comicPendingDelete: Comic?

    var body: some View {
        ScrollView {
            GeometryReader { proxy in
                let liveWidth = proxy.size.width
                let effectiveWidth = (isInspectorAnimating ? (frozenWidth ?? liveWidth) : (frozenWidth ?? liveWidth))
                let columns: [GridItem] = computedColumns(for: effectiveWidth, itemsPerRowPreference: itemsPerRowPreference)

                LazyVGrid(columns: columns, spacing: Layout.gridSpacing) {
                    ForEach(comics, id: \.id) { comic in
                        gridItem(for: comic)
                    }
                }
                .padding(Layout.gridPadding)
                .transaction { $0.animation = nil }
                .onAppear {
                    if frozenWidth == nil {
                        frozenWidth = liveWidth
                    }
                }
                .onChange(of: isInspectorAnimating) { _, animating in
                    if !animating {
                        // When animation ends, sync to the current width to avoid a final snap
                        frozenWidth = liveWidth
                    }
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    if !isInspectorAnimating {
                        frozenWidth = newWidth
                    }
                }
            }
        }
        .alert("Delete \"\(comicPendingDelete?.name ?? "Comic")\"?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let comic = comicPendingDelete {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let downloader = ComicDownloader()
                    downloader.deleteDownloadFolder(for: comic, in: docs)
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

    @ViewBuilder
    private func gridItem(for comic: Comic) -> some View {
        ComicTile(comic: comic,
                  isSelected: selectedComic == comic)
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture(count: 2)
                    .exclusively(before: TapGesture(count: 1))
                    .onEnded { result in
                        switch result {
                        case .first:
                            onOpenPages?(comic)
                        case .second:
                            selectedComic = comic
                        }
                    }
            )
            .contextMenu {
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

    private func computedColumns(for width: CGFloat, itemsPerRowPreference: Int, minTileWidth: CGFloat = 160) -> [GridItem] {
        let spacing = Layout.gridSpacing
        if itemsPerRowPreference > 0 {
            let count = itemsPerRowPreference
            return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
        } else {
            let count = max(1, Int((width + spacing) / (minTileWidth + spacing)))
            return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
        }
    }
}
