import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Comic.name) private var comics: [Comic]
    @Binding var isEditingComic: Bool
    @Binding var isDisplayingComicPages: Bool
    @Binding var isDisplayingReader: Bool
    @Binding var externalSelectedComic: Comic?
    @Binding var isDisplayingComicDetails: Bool
    @AppStorage(.settingsLibraryItemsPerRow) private var itemsPerRowPreference: Int = 6
    @State private var viewModel = LibraryViewModel()
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
                    isDisplayingComicPages = true
                },
                onRead: { comic in
                    externalSelectedComic = comic
                    isDisplayingReader = true
                },
                onOpenDetails: { comic in
                    externalSelectedComic = comic
                    isDisplayingComicDetails = true
                }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            let isSelectedComicBusy: Bool = {
                if let c = externalSelectedComic {
                    return viewModel.isFetching(comic: c) || viewModel.isUpdating(comic: c)
                }
                return false
            }()

            Button {
                viewModel.isAddingComic = true
            } label: {
                Label("Add Web Comic", systemImage: "plus.app")
            }
            .buttonStyle(.borderedProminent)

            Button {
                prepareExportProfile()
            } label: {
                Label("Export Profile", systemImage: "square.and.arrow.up")
            }
            .disabled(externalSelectedComic == nil || isSelectedComicBusy)
            .buttonStyle(.bordered)

            Button {
                isImporting = true
            } label: {
                Label("Import Profile", systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.bordered)

            Button {
                isDisplayingComicDetails = true
            } label: {
                Label("Details", systemImage: "info.circle")
            }
            .disabled(externalSelectedComic == nil || isSelectedComicBusy)
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
            .fileImporter(isPresented: $isImporting,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                do {
                    let urls = try result.get()
                    guard let url = urls.first else { return }

                    // Let the document handle security-scoped access and validation
                    let doc = try ComicProfileDocument.load(from: url)

                    _ = try viewModel.importProfileData(doc.data, context: context)
                    alertMessage = "Imported profile from \(url.lastPathComponent)."
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
                if let comic = externalSelectedComic {
                    ComicImagesView(comic: comic)
                } else {
                    ContentUnavailableView("No comic selected", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationDestination(isPresented: $isDisplayingReader) {
                if let comic = externalSelectedComic {
                    ComicReaderView(comic: comic)
                } else {
                    ContentUnavailableView("No comic selected", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationDestination(isPresented: $isDisplayingComicDetails) {
                if let comic = externalSelectedComic {
                    ComicDetailView(
                        comic: comic,
                        onRead: { isDisplayingReader = true },
                        onEdit: { isEditingComic = true },
                        onFetch: { viewModel.fetch(comic: comic, context: context) },
                        onUpdate: { viewModel.update(comic: comic, context: context) },
                        onOpenImages: { isDisplayingComicPages = true },
                        onCancelFetch: { viewModel.cancelFetch(for: comic) },
                        onCancelUpdate: { viewModel.cancelUpdate(for: comic) },
                        isFetching: viewModel.isFetching(comic: comic),
                        isUpdating: viewModel.isUpdating(comic: comic)
                    )
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
