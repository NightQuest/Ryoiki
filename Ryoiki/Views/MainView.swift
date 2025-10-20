import SwiftUI
import SwiftData

/// The app's main view that lists comics and provides tools to add and manage them.
struct MainView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Comic.name) private var comics: [Comic]

    @State var isAddingComic: Bool = false
    @State private var selectedComic: Comic?

    /// Shows either an empty state or the comics grid.
    @ViewBuilder
    private var content: some View {
        if comics.isEmpty {
            ContentUnavailableView("No web comics found",
                                   systemImage: "square.grid.2x2",
                                   description: Text("Add a web comic"))
        } else {
            ComicGrid(comics: comics, selectedComic: $selectedComic)
        }
    }

    var body: some View {
        content
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

// MARK: - Comic Grid

/// Displays comics in a responsive grid and supports clearing selection by tapping empty space.
struct ComicGrid: View {
    let comics: [Comic]
    @Binding var selectedComic: Comic?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Layout.gridColumns, spacing: Layout.gridSpacing) {
                ForEach(comics, id: \.self) { comic in
                    Button {
                        selectedComic = comic
                    } label: {
                        ComicTile(comic: comic, isSelected: selectedComic == comic)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Layout.gridPadding)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                selectedComic = nil
            }
        )
    }
}

// MARK: - Selection Border Modifier
struct SelectionBorder: ViewModifier {
    let isSelected: Bool
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.tint, lineWidth: isSelected ? 2 : 0)
            )
    }
}

extension View {
    func selectionBorder(_ isSelected: Bool) -> some View {
        modifier(SelectionBorder(isSelected: isSelected))
    }
}
