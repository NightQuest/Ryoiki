import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Comic.name) private var comics: [Comic]

    @State var isAddingComic: Bool = false
    @State private var selectedComic: Comic?

    /// Shows either an empty state or the comics grid.
    @ViewBuilder
    private var LibraryContent: some View {
        if comics.isEmpty {
            ContentUnavailableView("No web comics found",
                                   systemImage: "square.grid.2x2",
                                   description: Text("Add a web comic"))
        } else {
            ComicGrid(comics: comics, selectedComic: $selectedComic)
        }
    }

    var body: some View {
        LibraryContent
        .toolbar { mainToolbar }
        .sheet(isPresented: $isAddingComic) {
            AddComicView { input in
                let comic = Comic(
                    name: input.name,
                    author: input.author,
                    descriptionText: input.description,
                    url: input.url,
                    firstPageURL: input.firstPageURL,
                    selectorImage: input.selectorImage,
                    selectorTitle: input.selectorTitle,
                    selectorNext: input.selectorNext
                )
                context.insert(comic)
                do {
                    try context.save()
                } catch {
                    // Handle save error appropriately (e.g., show an alert/log)
                    print("Failed to save comic:", error.localizedDescription)
                }
                isAddingComic = false
            }
            .padding()
        }
    }

    // MARK: - Toolbars
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                isAddingComic.toggle()
            } label: {
                Label("Add Web Comic", systemImage: "plus.app")
            }
        }

        ToolbarItemGroup {
            Button {
            } label: {
                Label("Fetch", systemImage: "tray.and.arrow.down")
            }
            .disabled(selectedComic == nil)

            Button {
            } label: {
                Label("Update", systemImage: "square.and.arrow.down")
            }
            .disabled(true)
        }
    }
}
