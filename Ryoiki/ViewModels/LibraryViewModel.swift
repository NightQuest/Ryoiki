import Foundation
import SwiftData
import SwiftUI
import Observation

nonisolated private func applyCachedFieldUpdates(for comic: Comic, using fm: FileManager) -> Bool {
    let pages = comic.pages
    let pageCount = pages.count
    var imageCount = 0
    var downloadedCount = 0
    var firstCoverPath: String = comic.coverFilePath

    for page in pages {
        imageCount += page.images.count
        for image in page.images {
            let path = image.downloadPath
            if path.isEmpty { continue }
            let fsPath: String
            if let url = URL(string: path), url.scheme != nil {
                fsPath = url.path
            } else {
                fsPath = path
            }
            if fm.fileExists(atPath: fsPath) {
                downloadedCount += 1
                if firstCoverPath.isEmpty { firstCoverPath = fsPath }
            }
        }
    }

    var didChange = false
    if comic.pageCount != pageCount { comic.pageCount = pageCount; didChange = true }
    if comic.imageCount != imageCount { comic.imageCount = imageCount; didChange = true }
    if comic.downloadedImageCount != downloadedCount { comic.downloadedImageCount = downloadedCount; didChange = true }
    if comic.coverFilePath.isEmpty && !firstCoverPath.isEmpty { comic.coverFilePath = firstCoverPath; didChange = true }
    return didChange
}

@Observable @MainActor
final class LibraryViewModel {
    var isAddingComic: Bool = false

    @ObservationIgnored private var fetchTasks: [UUID: Task<Void, Never>] = [:]
    var fetchingComicIDs: Set<UUID> = []

    @ObservationIgnored private var updateTasks: [UUID: Task<Void, Never>] = [:]
    var updatingComicIDs: Set<UUID> = []

    @ObservationIgnored private var isBackfilling = false

    func isFetching(comic: Comic) -> Bool { fetchingComicIDs.contains(comic.id) }
    func isUpdating(comic: Comic) -> Bool { updatingComicIDs.contains(comic.id) }

    // Start fetching pages for a given comic
    func fetch(comic: Comic, context: ModelContext) {
        // Avoid duplicate tasks
        guard fetchTasks[comic.id] == nil else { return }

        // Record UI state on main actor
        fetchingComicIDs.insert(comic.id)

        // Capture only what we need for background work
        let comicID = comic.id
        // Create a background context from the same container
        let container = context.container

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            // Build background context and disable autosave for batch work
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            // Resolve the comic in the background context by ID to avoid cross-context object usage
            // If resolution fails, we bail early (comic might have been deleted)
            guard let bgComic = try? bgContext.fetch(FetchDescriptor<Comic>(predicate: #Predicate { $0.id == comicID })).first else {
                await MainActor.run { [weak self] in
                    self?.fetchingComicIDs.remove(comicID)
                    self?.fetchTasks[comicID] = nil
                }
                return
            }

            let cm = await ComicManager(httpClient: HTTPClient())
            do {
                // Perform heavy work off-main
                _ = try await cm.fetchPages(for: bgComic, context: bgContext)
                try? Task.checkCancellation()
            } catch is CancellationError {
                // Swallow cancellation
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Network cancelled
            } catch {
                print("Fetch failed: \(error)")
            }

            // Clear UI state back on main actor
            await MainActor.run { [weak self] in
                self?.fetchingComicIDs.remove(comicID)
                self?.fetchTasks[comicID] = nil
            }
        }

        // Track the task on main actor
        fetchTasks[comic.id] = task
    }

    // Cancel an in-flight fetch for a specific comic
    func cancelFetch(for comic: Comic) {
        fetchTasks[comic.id]?.cancel()
    }

    // Start updating (downloading) images for a given comic to the documents directory
    func update(comic: Comic, context: ModelContext) {
        // Avoid duplicate tasks
        guard updateTasks[comic.id] == nil else { return }

        // Record UI state on main actor
        updatingComicIDs.insert(comic.id)

        let comicID = comic.id
        let container = context.container

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false

            // Resolve comic in background context
            guard let bgComic = try? bgContext.fetch(FetchDescriptor<Comic>(predicate: #Predicate { $0.id == comicID })).first else {
                await MainActor.run { [weak self] in
                    self?.updatingComicIDs.remove(comicID)
                    self?.updateTasks[comicID] = nil
                }
                return
            }

            let cm = await ComicManager(httpClient: HTTPClient())
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            do {
                try? Task.checkCancellation()
                _ = try await cm.downloadImages(for: bgComic, to: docs, context: bgContext, overwrite: false)
            } catch is CancellationError {
                // Swallow cancellation
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Network cancelled
            } catch {
                print("Update failed: \(error)")
            }

            await MainActor.run { [weak self] in
                self?.updatingComicIDs.remove(comicID)
                self?.updateTasks[comicID] = nil
            }
        }

        updateTasks[comic.id] = task
    }

    // Cancel an in-flight update for a specific comic
    func cancelUpdate(for comic: Comic) {
        updateTasks[comic.id]?.cancel()
    }

    // Add a new comic using the editor input
    func addComic(input: ComicInput, context: ModelContext) {
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

    // Edit an existing comic in place, including renaming its folder and updating stored paths when the name changes
    func editComic(comic: Comic, input: ComicInput, context: ModelContext) {
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
                let comicID = comic.id
                let container = context.container
                // Precompute sanitized names on the main actor to avoid calling main-actor-isolated APIs off-main
                let oldSanitized = oldName.sanitizedForFileName()
                let newSanitized = input.name.sanitizedForFileName()
                Task.detached(priority: .utility) {
                    let bgContext = ModelContext(container)
                    bgContext.autosaveEnabled = false

                    // Resolve comic in background context by ID
                    guard let bgComic = try? bgContext.fetch(FetchDescriptor<Comic>(predicate: #Predicate { $0.id == comicID })).first else {
                        return
                    }

                    let fm = FileManager.default
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let oldFolder = docs.appendingPathComponent(oldSanitized)
                    let newFolder = docs.appendingPathComponent(newSanitized)

                    if fm.fileExists(atPath: oldFolder.path) {
                        if oldFolder != newFolder {
                            if fm.fileExists(atPath: newFolder.path) {
                                // Destination exists; avoid destructive merge
                            } else {
                                try? fm.moveItem(at: oldFolder, to: newFolder)
                            }
                        }

                        let oldPath = oldFolder.path
                        let newPath = newFolder.path

                        // Update stored paths to reflect the new folder location
                        for page in bgComic.pages {
                            for image in page.images {
                                guard !image.downloadPath.isEmpty else { continue }
                                if let url = URL(string: image.downloadPath), url.scheme != nil {
                                    let updatedPath = url.path.replacingOccurrences(of: oldPath, with: newPath)
                                    let newFileURL = URL(fileURLWithPath: updatedPath)
                                    image.downloadPath = newFileURL.absoluteString
                                } else {
                                    image.downloadPath = image.downloadPath.replacingOccurrences(of: oldPath, with: newPath)
                                }
                            }
                        }
                        try? bgContext.save()
                    }
                }
            }
        } catch {
            print("Failed to save edits:", error.localizedDescription)
        }
    }

    // MARK: - Profile Export/Import

    func makeProfile(for comic: Comic) -> ComicProfile {
        ComicProfile(from: comic)
    }

    func exportProfileData(for comic: Comic) throws -> Data {
        let profile = makeProfile(for: comic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profile)
    }

    func importProfileData(_ data: Data, context: ModelContext) throws -> Comic {
        let decoder = JSONDecoder()
        let profile = try decoder.decode(ComicProfile.self, from: data)
        let comic = Comic(
            name: profile.name,
            author: profile.author,
            descriptionText: profile.descriptionText,
            url: profile.url,
            firstPageURL: profile.firstPageURL,
            selectorImage: profile.selectorImage,
            selectorTitle: profile.selectorTitle,
            selectorNext: profile.selectorNext
        )
        context.insert(comic)
        try context.save()
        return comic
    }

    // Backfill cached counts/paths for existing libraries. Safe to call multiple times.
    func backfillCachedFields(context: ModelContext) {
        Task { @MainActor in
            if self.isBackfilling { return }
            self.isBackfilling = true
        }

        let container = context.container
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let bg = ModelContext(container)
            bg.autosaveEnabled = false

            do {
                let comics: [Comic] = try bg.fetch(FetchDescriptor<Comic>())
                guard !comics.isEmpty else {
                    await MainActor.run { [weak self] in
                        self?.isBackfilling = false
                    }
                    return
                }

                let fm = FileManager.default
                var updated = 0

                for comic in comics {
                    if applyCachedFieldUpdates(for: comic, using: fm) {
                        updated += 1
                    }

                    // Save periodically
                    if updated % 25 == 0 { try? bg.save() }
                }

                try? bg.save()
                await MainActor.run { [weak self] in
                    self?.isBackfilling = false
                }
            } catch {
                // Best-effort backfill; ignore errors
                await MainActor.run { [weak self] in
                    self?.isBackfilling = false
                }
            }
        }
    }

    deinit {
        for (_, t) in fetchTasks { t.cancel() }
        for (_, t) in updateTasks { t.cancel() }
    }
}
