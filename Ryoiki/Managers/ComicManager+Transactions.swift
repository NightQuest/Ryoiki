import Foundation
import SwiftData

extension ComicManager {
    func addComic(input: ComicInput, context: ModelContext) -> Comic {
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
        try? context.save()
        return comic
    }

    func editComic(comicID: UUID, input: ComicInput, container: ModelContainer) {
        let bgContext = ModelContext(container)
        bgContext.autosaveEnabled = false
        guard let bgComic = try? bgContext.fetch(
            FetchDescriptor<Comic>(predicate: #Predicate { $0.id == comicID })
        ).first else {
            return
        }

        let oldName = bgComic.name

        bgComic.name = input.name
        bgComic.author = input.author
        bgComic.descriptionText = input.description
        bgComic.url = input.url
        bgComic.firstPageURL = input.firstPageURL
        bgComic.selectorImage = input.selectorImage
        bgComic.selectorTitle = input.selectorTitle
        bgComic.selectorNext = input.selectorNext

        try? bgContext.save()

        if oldName != input.name {
            let oldSanitized = oldName.sanitizedForFileName()
            let newSanitized = input.name.sanitizedForFileName()
            let fileManager = FileManager.default
            guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

            let oldFolderURL = documentsURL.appendingPathComponent(oldSanitized)
            let newFolderURL = documentsURL.appendingPathComponent(newSanitized)

            if !fileManager.fileExists(atPath: newFolderURL.path) {
                do {
                    try fileManager.moveItem(at: oldFolderURL, to: newFolderURL)
                } catch {
                    print("Failed to rename folder from \(oldFolderURL.path) to \(newFolderURL.path): \(error)")
                }
            }

            for page in bgComic.pages {
                for image in page.images {
                    guard let url = image.fileURL, url.scheme != nil else { continue }
                    let oldPrefix = oldFolderURL.path
                    let newPrefix = newFolderURL.path
                    if url.path.hasPrefix(oldPrefix) {
                        let relativePath = url.path.dropFirst(oldPrefix.count)
                        let newURL = URL(fileURLWithPath: newPrefix + relativePath)
                        image.fileURL = newURL
                    }
                }
            }

            try? bgContext.save()
        }
    }

    func fetchPagesForComic(comicID: UUID, container: ModelContainer) async {
        let bgContext = ModelContext(container)
        bgContext.autosaveEnabled = false
        guard let bgComic = try? bgContext.fetch(
            FetchDescriptor<Comic>(predicate: #Predicate { $0.id == comicID })
        ).first else { return }
        do {
            _ = try await fetchPages(for: bgComic, context: bgContext)
            try? Task.checkCancellation()
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            print("Error fetching pages for comic \(comicID): \(error)")
        }
    }

    func downloadImagesForComic(comicID: UUID, container: ModelContainer, documentsURL: URL) async {
        let bgContext = ModelContext(container)
        bgContext.autosaveEnabled = false
        guard let bgComic = try? bgContext.fetch(
            FetchDescriptor<Comic>(predicate: #Predicate { $0.id == comicID })
        ).first else { return }
        do {
            try? Task.checkCancellation()
            _ = try await downloadImages(for: bgComic, to: documentsURL, context: bgContext, overwrite: false)
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            print("Error downloading images for comic \(comicID): \(error)")
        }
    }

    func exportProfileData(for comic: Comic) throws -> Data {
        let profile = ComicProfile(from: comic)
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
