import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Comic.name) private var comics: [Comic]
    @Binding var isEditingComic: Bool
    @Binding var isDisplayingComicPages: Bool
    @Binding var externalSelectedComic: Comic?
    @Binding var displayInspector: Bool
    @AppStorage(.settingsLibraryItemsPerRow) private var itemsPerRowPreference: Int = 6
    @State private var viewModel = LibraryViewModel()
    @State private var pagesComic: Comic?
    @State private var isDisplayingReader: Bool = false
    @State private var alertMessage: String?

    @State private var exportDocument: ComicProfileDocument?
    @State private var isExporting: Bool = false
    @State private var isImporting: Bool = false

    @ViewBuilder
    private var LibraryContent: some View {
        if comics.isEmpty {
            VStack(spacing: 24) {
                ContentUnavailableView("No web comics found",
                                       systemImage: "square.grid.2x2",
                                       description: Text("Add a web comic"))
                .padding()
            }
            .padding(.horizontal)
        } else {
            ComicGrid(
                comics: comics,
                selectedComic: $externalSelectedComic,
                itemsPerRowPreference: itemsPerRowPreference,
                fetchingComicIDs: viewModel.fetchingComicIDs,
                updatingComicIDs: viewModel.updatingComicIDs,
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
                },
                onOpenPages: { comic in
                    externalSelectedComic = comic
                    if comic.hasAnyDownloadedImage() {
                        pagesComic = comic
                        isDisplayingComicPages = true
                        displayInspector = false
                    }
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
                    if !viewModel.isFetching(comic: comic) {
                        viewModel.fetch(comic: comic, context: context)
                    } else {
                        viewModel.cancelFetch(for: comic)
                    }
                }
            } label: {
                if let comic = externalSelectedComic, viewModel.isFetching(comic: comic) {
                    Label("Cancel", systemImage: "xmark.circle")
                } else {
                    Label("Fetch", systemImage: "tray.and.arrow.down")
                }
            }
            .disabled(externalSelectedComic == nil)
            .buttonStyle(.bordered)

            Button {
                if let comic = externalSelectedComic {
                    if !viewModel.isUpdating(comic: comic) {
                        viewModel.update(comic: comic, context: context)
                    } else {
                        viewModel.cancelUpdate(for: comic)
                    }
                }
            } label: {
                if let comic = externalSelectedComic, viewModel.isUpdating(comic: comic) {
                    Label("Cancel", systemImage: "xmark.circle")
                } else {
                    Label("Update", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(externalSelectedComic == nil)
            .buttonStyle(.bordered)

            Button {
                prepareExportProfile()
            } label: {
                Label("Export Profile", systemImage: "square.and.arrow.up")
            }
            .disabled(externalSelectedComic == nil)
            .buttonStyle(.bordered)

            Button {
                isImporting = true
            } label: {
                Label("Import Profile", systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.bordered)

            Button {
                // Open the selected comic in the full-window reader
                pagesComic = externalSelectedComic
                isDisplayingReader = true
                displayInspector = false
            } label: {
                Label("Read", systemImage: "book")
            }
            .disabled(!(externalSelectedComic?.hasAnyDownloadedImage() ?? false))
            .buttonStyle(.bordered)

            Button {
                pagesComic = externalSelectedComic
                isDisplayingComicPages = true
            } label: {
                Label("Images", systemImage: "square.grid.3x3")
            }
            .disabled(!(externalSelectedComic?.hasAnyDownloadedImage() ?? false))
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
            .fileExporter(isPresented: $isExporting,
                          document: exportDocument,
                          contentType: .json,
                          defaultFilename: exportDefaultFilename(),
                          onCompletion: { result in
                switch result {
                case .success(let url):
                    alertMessage = "Exported profile to \(url.lastPathComponent)."
                case .failure(let error):
                    alertMessage = "Failed to export: \(error.localizedDescription)"
                }
            })
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                do {
                    let urls = try result.get()
                    if let url = urls.first {
                        let data = try Data(contentsOf: url)
                        _ = try viewModel.importProfileData(data, context: context)
                        alertMessage = "Imported profile from \(url.lastPathComponent)."
                    }
                } catch {
                    alertMessage = "Failed to import: \(error.localizedDescription)"
                }
            }
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
            .navigationDestination(isPresented: $isDisplayingComicPages) {
                if let comic = pagesComic {
                    ComicImagesView(comic: comic)
                } else {
                    ContentUnavailableView("No comic selected", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationDestination(isPresented: $isDisplayingReader) {
                if let comic = pagesComic {
                    ComicReaderView(comic: comic)
                } else {
                    ContentUnavailableView("No comic selected", systemImage: "exclamationmark.triangle")
                }
            }
            .alert(item: Binding(
                get: { alertMessage.map { IdentifiedString(message: $0) } },
                set: { newVal in alertMessage = newVal?.message })
            ) { item in
                Alert(title: Text(item.message))
            }
        }
    }

    private func prepareExportProfile() {
        guard let comic = externalSelectedComic else { return }
        do {
            let data = try viewModel.exportProfileData(for: comic)
            exportDocument = ComicProfileDocument(data: data)
            isExporting = true
        } catch {
            alertMessage = "Failed to export: \(error.localizedDescription)"
        }
    }

    private func exportDefaultFilename() -> String {
        let base = externalSelectedComic?.name ?? "ComicProfile"
        return base.sanitizedForFileName() + ".json"
    }
}

private struct IdentifiedString: Identifiable {
    let id = UUID()
    let message: String
}
