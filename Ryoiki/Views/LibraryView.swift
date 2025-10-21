import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Comic.name) private var comics: [Comic]
    @State private var isAddingComic: Bool = false
    @Binding var externalSelectedComic: Comic?
    @Binding var displayInspector: Bool
    @Binding var isInspectorAnimating: Bool
    @AppStorage("library.itemsPerRow") private var itemsPerRowPreference: Int = 6
    @State private var isFetching: Bool = false
    @State private var isUpdating: Bool = false
    @State private var fetchTask: Task<Void, Never>?
    @State private var updateTask: Task<Void, Never>?

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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                isAddingComic = true
                displayInspector = false
            } label: {
                Label("Add Web Comic", systemImage: "plus.app")
            }
            .buttonStyle(.borderedProminent)

            Button {
                if !isFetching {
                    fetchSelected()
                } else {
                    // Stop fetching
                    fetchTask?.cancel()
                }
            } label: {
                if isFetching { ProgressView() } else { Label("Fetch", systemImage: "tray.and.arrow.down") }
            }
            .disabled(externalSelectedComic == nil)
            .buttonStyle(.bordered)

            Button {
                if !isUpdating {
                    updateSelected()
                } else {
                    // Stop updating
                    updateTask?.cancel()
                }
            } label: {
                if isUpdating { ProgressView() } else { Label("Update", systemImage: "square.and.arrow.down") }
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
        NavigationStack {
            LibraryContent
                .toolbar { toolbarContent }
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

    private func fetchSelected() {
        guard let comic = externalSelectedComic else { return }
        isFetching = true
        fetchTask = Task { @MainActor in
            defer {
                isFetching = false
                fetchTask = nil
            }
            let scraper = ComicDownloader()
            do {
                _ = try await scraper.fetchPages(for: comic, context: context)
            } catch is CancellationError {
                // Fetch cancelled by user
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Network task cancelled by user
            } catch {
                print("Fetch failed: \(error)")
            }
        }
    }

    private func updateSelected() {
        guard let comic = externalSelectedComic else { return }
        isUpdating = true
        updateTask = Task { @MainActor in
            defer {
                isUpdating = false
                updateTask = nil
            }
            let scraper = ComicDownloader()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            do {
                _ = try await scraper.downloadImages(for: comic, to: docs, context: context, overwrite: false)
            } catch is CancellationError {
                // Update cancelled by user
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Network task cancelled by user
            } catch {
                print("Update failed: \(error)")
            }
        }
    }
}
