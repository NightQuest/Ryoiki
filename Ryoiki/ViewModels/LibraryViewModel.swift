import Foundation
import SwiftData
import SwiftUI
import Observation

@Observable @MainActor
final class LibraryViewModel {
    var isAddingComic: Bool = false
    var isFetching: Bool = false
    var isUpdating: Bool = false

    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    // Start fetching pages for a given comic
    func fetch(comic: Comic, context: ModelContext) {
        guard !isFetching else { return }
        isFetching = true
        fetchTask = Task { @MainActor in
            defer {
                self.isFetching = false
                self.fetchTask = nil
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

    // Cancel an in-flight fetch
    func cancelFetch() {
        fetchTask?.cancel()
    }

    // Start updating (downloading) images for a given comic to the documents directory
    func update(comic: Comic, context: ModelContext) {
        guard !isUpdating else { return }
        isUpdating = true
        updateTask = Task { @MainActor in
            defer {
                self.isUpdating = false
                self.updateTask = nil
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

    // Cancel an in-flight update
    func cancelUpdate() {
        updateTask?.cancel()
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
                let oldFolder = docs.appendingPathComponent(sanitizeFilename(oldName))
                let newFolder = docs.appendingPathComponent(sanitizeFilename(input.name))

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
                        guard !page.downloadPath.isEmpty else { continue }
                        if let url = URL(string: page.downloadPath), url.scheme != nil {
                            let updatedPath = url.path.replacingOccurrences(of: oldPath, with: newPath)
                            let newFileURL = URL(fileURLWithPath: updatedPath)
                            page.downloadPath = newFileURL.absoluteString
                        } else {
                            page.downloadPath = page.downloadPath.replacingOccurrences(of: oldPath, with: newPath)
                        }
                    }
                    try? context.save()
                }
            }
        } catch {
            print("Failed to save edits:", error.localizedDescription)
        }
    }
}
