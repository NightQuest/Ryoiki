import Foundation
import SwiftData
import SwiftUI
import Observation

@Observable @MainActor
final class LibraryViewModel {
    var isAddingComic: Bool = false

    @ObservationIgnored private var fetchTasks: [UUID: Task<Void, Never>] = [:]
    var fetchingComicIDs: Set<UUID> = []

    @ObservationIgnored private var updateTasks: [UUID: Task<Void, Never>] = [:]
    var updatingComicIDs: Set<UUID> = []

    func isFetching(comic: Comic) -> Bool { fetchingComicIDs.contains(comic.id) }
    func isUpdating(comic: Comic) -> Bool { updatingComicIDs.contains(comic.id) }

    // Start fetching pages for a given comic
    func fetch(comic: Comic, context: ModelContext) {
        guard fetchTasks[comic.id] == nil else { return }
        fetchingComicIDs.insert(comic.id)
        fetchTasks[comic.id] = Task { @MainActor in
            defer {
                fetchingComicIDs.remove(comic.id)
                fetchTasks[comic.id] = nil
            }
            let cm = ComicManager()
            do {
                _ = try await cm.fetchPages(for: comic, context: context)
            } catch is CancellationError {
                // Fetch cancelled by user
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Network task cancelled by user
            } catch {
                print("Fetch failed: \(error)")
            }
        }
    }

    // Cancel an in-flight fetch for a specific comic
    func cancelFetch(for comic: Comic) {
        fetchTasks[comic.id]?.cancel()
    }

    // Start updating (downloading) images for a given comic to the documents directory
    func update(comic: Comic, context: ModelContext) {
        guard updateTasks[comic.id] == nil else { return }
        updatingComicIDs.insert(comic.id)
        updateTasks[comic.id] = Task { @MainActor in
            defer {
                updatingComicIDs.remove(comic.id)
                updateTasks[comic.id] = nil
            }
            let cm = ComicManager()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            do {
                _ = try await cm.downloadImages(for: comic, to: docs, context: context, overwrite: false)
            } catch is CancellationError {
                // Update cancelled by user
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Network task cancelled by user
            } catch {
                print("Update failed: \(error)")
            }
        }
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
                let fm = FileManager.default
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let oldFolder = docs.appendingPathComponent(oldName.sanitizedForFileName())
                let newFolder = docs.appendingPathComponent(input.name.sanitizedForFileName())

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
                    for page in comic.pages {
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
                    try? context.save()
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
}
