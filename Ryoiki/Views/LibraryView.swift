import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Comic.name) private var comics: [Comic]

    @State private var isAddingComic: Bool = false
    // Selection binding from root
    @Binding var externalSelectedComic: Comic?
    @Binding var displayInspector: Bool
    @Binding var isInspectorAnimating: Bool
    @AppStorage("library.itemsPerRow") private var itemsPerRowPreference: Int = 6

    /// Shows either an empty state or the comics grid.
    @ViewBuilder
    private var LibraryContent: some View {
        if comics.isEmpty {
            VStack(spacing: 24) {
                ContentUnavailableView("No web comics found",
                                       systemImage: "square.grid.2x2",
                                       description: Text("Add a web comic"))
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal)
        } else {
            ComicGrid(comics: comics,
                      selectedComic: $externalSelectedComic,
                      isInspectorAnimating: $isInspectorAnimating,
                      itemsPerRowPreference: itemsPerRowPreference)
        }
    }

    var body: some View {
        NavigationStack {
            LibraryContent
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAddingComic = true
                            displayInspector = false
                        } label: {
                            Label("Add Web Comic", systemImage: "plus.app")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    ToolbarItem {
                        Button { } label: {
                            Label("Fetch", systemImage: "tray.and.arrow.down")
                        }
                        .disabled(externalSelectedComic == nil)
                        .buttonStyle(.bordered)
                    }

                    ToolbarItem {
                        Button { } label: {
                            Label("Update", systemImage: "square.and.arrow.down")
                        }
                        .disabled(externalSelectedComic == nil)
                        .buttonStyle(.bordered)
                    }
                }
                .navigationDestination(isPresented: $isAddingComic) {
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
                            print("Failed to save comic:", error.localizedDescription)
                        }
                    }
                }
        }
    }
}
