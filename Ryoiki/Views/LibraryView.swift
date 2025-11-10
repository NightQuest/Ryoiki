import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Foundation

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.comicManager) private var comicManager
    @Query(sort: \Comic.name) private var comics: [Comic]
    @Binding var isEditingComic: Bool
    @Binding var isDisplayingComicPages: Bool
    @Binding var isDisplayingReader: Bool
    @Binding var externalSelectedComic: Comic?
    @Binding var isDisplayingComicDetails: Bool
    @AppStorage(.settingsLibraryItemsPerRow) private var itemsPerRowPreference: Int = 6
    @State private var alertMessage: String?

    @State private var exportDocument: ComicProfileDocument?
    @State private var isExporting: Bool = false
    @State private var isImporting: Bool = false

    @State private var isAddingComic: Bool = false
    @State private var fetchingComicIDs: Set<UUID> = []
    @State private var updatingComicIDs: Set<UUID> = []
    @State private var fetchTasks: [UUID: Task<Void, Never>] = [:]
    @State private var updateTasks: [UUID: Task<Void, Never>] = [:]

    private struct LibraryEmptyStateView: View {
        var body: some View {
            VStack(spacing: 24) {
                ContentUnavailableView("No web comics found",
                                       systemImage: "square.grid.2x2",
                                       description: Text("Add a web comic"))
                .padding()
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var LibraryContent: some View {
        if comics.isEmpty {
            LibraryEmptyStateView()
        } else {
            ComicGrid(
                comics: comics,
                selectedComic: $externalSelectedComic,
                itemsPerRowPreference: itemsPerRowPreference,
                fetchingComicIDs: fetchingComicIDs,
                updatingComicIDs: updatingComicIDs,
                onEdit: { comic in
                    externalSelectedComic = comic
                    isEditingComic = true
                },
                onFetch: { comic in
                    externalSelectedComic = comic
                    fetch(comic: comic, context: context)
                },
                onUpdate: { comic in
                    externalSelectedComic = comic
                    update(comic: comic, context: context)
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

    private var selectedComicBusy: Bool {
        if let c = externalSelectedComic {
            return isFetching(comic: c) || isUpdating(comic: c)
        }
        return false
    }

    @ViewBuilder
    private func addButton() -> some View {
        Button {
            isAddingComic = true
        } label: {
            Label("Add Web Comic", systemImage: "plus.app")
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private func actionButtons() -> some View {
        Button {
            prepareExportProfile()
        } label: {
            Label("Export Profile", systemImage: "square.and.arrow.up")
        }
        .disabled(externalSelectedComic == nil || selectedComicBusy)
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
        .disabled(externalSelectedComic == nil)
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func itemsPerRowSlider(width: CGFloat, smallControl: Bool = true) -> some View {
        Slider(value: Binding<Double>(
            get: { Double(itemsPerRowPreference) },
            set: { itemsPerRowPreference = Int($0.rounded()) }
        ), in: 2...10, step: 1)
        .labelsHidden()
        .controlSize(smallControl ? .small : .regular)
        .frame(width: width)
        .help("Adjust items per row")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
#if os(iOS)
        ToolbarItemGroup(placement: .navigationBarLeading) {
            addButton()
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            actionButtons()
            if horizontalSizeClass != .compact {
                itemsPerRowSlider(width: 120)
            }
        }

        if horizontalSizeClass == .compact {
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(.secondary)
                    itemsPerRowSlider(width: 140)
                        .tint(.accentColor)
                }
                .accessibilityLabel(Text("Adjust items per row"))
            }
        }
#else
        // macOS (and other platforms): original single group with Spacer, reusing shared items
        ToolbarItemGroup {
            addButton()
            actionButtons()
            Spacer()
            itemsPerRowSlider(width: 120)
        }
#endif
    }

    var body: some View {
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

                    let doc = try ComicProfileDocument.load(from: url)

                    _ = try comicManager.importProfileData(doc.data, context: context)
                    alertMessage = "Imported profile from \(url.lastPathComponent)."
                } catch {
                    alertMessage = "Failed to import: \(error.localizedDescription)"
                }
            }
            .navigationDestination(isPresented: $isAddingComic) {
                ComicEditorView { input in
                    addComic(input: input, context: context)
                }
            }
            .navigationDestination(isPresented: $isEditingComic) {
                if let comic = externalSelectedComic {
                    ComicEditorView(comicToEdit: comic) { input in
                        editComic(comic: comic, input: input, context: context)
                    }
                } else {
                    // Fallback if selection was lost; present empty editor
                    // (should not happen normally)
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
                        onFetch: { fetch(comic: comic, context: context) },
                        onUpdate: { update(comic: comic, context: context) },
                        onOpenImages: { isDisplayingComicPages = true },
                        onCancelFetch: { cancelFetch(for: comic) },
                        onCancelUpdate: { cancelUpdate(for: comic) },
                        isFetching: isFetching(comic: comic),
                        isUpdating: isUpdating(comic: comic)
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
            let data = try comicManager.exportProfileData(for: comic)
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

    private func isFetching(comic: Comic) -> Bool { fetchingComicIDs.contains(comic.id) }
    private func isUpdating(comic: Comic) -> Bool { updatingComicIDs.contains(comic.id) }

    private func fetch(comic: Comic, context: ModelContext) {
        guard fetchTasks[comic.id] == nil else { return }
        fetchingComicIDs.insert(comic.id)
        let comicID = comic.id
        let container = context.container

        let task = Task.detached(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                _ = await comicManager.fetchPagesForComic(comicID: comicID, container: container)
            } catch is CancellationError {
            } catch let urlError as URLError where urlError.code == .cancelled {
            } catch {
                print("Fetch failed: \(error)")
            }
            await MainActor.run {
                fetchingComicIDs.remove(comicID)
                fetchTasks[comicID] = nil
            }
        }
        fetchTasks[comic.id] = task
    }

    private func cancelFetch(for comic: Comic) { fetchTasks[comic.id]?.cancel() }

    private func update(comic: Comic, context: ModelContext) {
        guard updateTasks[comic.id] == nil else { return }
        updatingComicIDs.insert(comic.id)
        let comicID = comic.id
        let container = context.container

        let task = Task.detached(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                _ = await comicManager.downloadImagesForComic(comicID: comicID, container: container, documentsURL: docs)
            } catch is CancellationError {
            } catch let urlError as URLError where urlError.code == .cancelled {
            } catch {
                print("Update failed: \(error)")
            }
            await MainActor.run {
                updatingComicIDs.remove(comicID)
                updateTasks[comicID] = nil
            }
        }
        updateTasks[comic.id] = task
    }

    private func cancelUpdate(for comic: Comic) { updateTasks[comic.id]?.cancel() }

    private func addComic(input: ComicInput, context: ModelContext) {
        _ = comicManager.addComic(input: input, context: context)
    }

    private func editComic(comic: Comic, input: ComicInput, context: ModelContext) {
        let oldName = comic.name
        comic.name = input.name
        comic.author = input.author
        comic.descriptionText = input.description
        comic.url = input.url
        comic.firstPageURL = input.firstPageURL
        comic.selectorImage = input.selectorImage
        comic.selectorTitle = input.selectorTitle
        comic.selectorNext = input.selectorNext
        do {
            try context.save()
            if oldName != input.name {
                comicManager.editComic(comicID: comic.id, input: input, container: context.container)
            }
        } catch {
            print("Failed to save edits:", error.localizedDescription)
        }
    }
}

private struct IdentifiedString: Identifiable {
    let id = UUID()
    let message: String
}
