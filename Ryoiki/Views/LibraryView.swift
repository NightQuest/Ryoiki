import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Comic.name) private var comics: [Comic]
    @Binding var isEditingComic: Bool
    @Binding var externalSelectedComic: Comic?
    @Binding var displayInspector: Bool
    @Binding var isInspectorAnimating: Bool
    @AppStorage("library.itemsPerRow") private var itemsPerRowPreference: Int = 6
    @State private var viewModel = LibraryViewModel()

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
            ComicGrid(
                comics: comics,
                selectedComic: $externalSelectedComic,
                isInspectorAnimating: $isInspectorAnimating,
                itemsPerRowPreference: itemsPerRowPreference,
                onEdit: { comic in
                    externalSelectedComic = comic
                    isEditingComic = true
                    displayInspector = false
                },
                onFetch: { comic in
                    externalSelectedComic = comic
                    viewModel.fetch(comic: comic, context: context)
                },
                onUpdate: { comic in
                    externalSelectedComic = comic
                    viewModel.update(comic: comic, context: context)
                }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                viewModel.isAddingComic = true
                displayInspector = false
            } label: {
                Label("Add Web Comic", systemImage: "plus.app")
            }
            .buttonStyle(.borderedProminent)

            Button {
                isEditingComic = true
                displayInspector = false
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .disabled(externalSelectedComic == nil)
            .buttonStyle(.bordered)

            Button {
                if let comic = externalSelectedComic {
                    if !viewModel.isFetching {
                        viewModel.fetch(comic: comic, context: context)
                    } else {
                        viewModel.cancelFetch()
                    }
                }
            } label: {
                if viewModel.isFetching { ProgressView() } else { Label("Fetch", systemImage: "tray.and.arrow.down") }
            }
            .disabled(externalSelectedComic == nil)
            .buttonStyle(.bordered)

            Button {
                if let comic = externalSelectedComic {
                    if !viewModel.isUpdating {
                        viewModel.update(comic: comic, context: context)
                    } else {
                        viewModel.cancelUpdate()
                    }
                }
            } label: {
                if viewModel.isUpdating { ProgressView() } else { Label("Update", systemImage: "square.and.arrow.down") }
            }
            .disabled(externalSelectedComic == nil)
            .buttonStyle(.bordered)

            Spacer()

            Slider(value: Binding<Double>(
                get: { Double(itemsPerRowPreference) },
                set: { itemsPerRowPreference = Int($0.rounded()) }
            ), in: 2...10, step: 1)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 120)
            .help("Adjust items per row")
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            LibraryContent
                .toolbar { toolbarContent }
                .navigationDestination(isPresented: $viewModel.isAddingComic) {
                    ComicEditorView { input in
                        viewModel.addComic(input: input, context: context)
                    }
                }
                .navigationDestination(isPresented: $isEditingComic) {
                    if let comic = externalSelectedComic {
                        ComicEditorView(comicToEdit: comic) { input in
                            viewModel.editComic(comic: comic, input: input, context: context)
                        }
                    } else {
                        // Fallback if selection was lost; present empty editor (should not happen normally)
                        ComicEditorView { _ in }
                    }
                }
        }
    }
}
