//
//  ComicManager+Downloading.swift
//  Ryoiki
//

import Foundation
import SwiftData

// MARK: - Image Downloading
extension ComicManager {
    private struct DownloadResult {
        let imageID: UUID
        let fileURLString: String
        let coverData: Data?
        let wrote: Bool
    }

    private func downloadAsset(
        page: ComicPage,
        image: ComicImage,
        comicFolder: URL,
        overwrite: Bool,
        naming: PageNamingContext
    ) async throws -> DownloadResult {
        let fileManager = FileManager.default
        guard let refererURL = URL(string: page.pageURL) else { return .init(imageID: image.id, fileURLString: "", coverData: nil, wrote: false) }

        let index = naming.formattedIndex
        let titlePart: String = page.title.isEmpty ? "" : " - " + page.title.sanitizedForFileName()

        // Data URL path
        if image.imageURL.hasPrefix("data:") {
            guard let (mediatype, data) = decodeDataURL(image.imageURL) else {
                return .init(imageID: image.id, fileURLString: "", coverData: nil, wrote: false)
            }
            let ext = fileExtension(contentType: mediatype, urlExtension: nil, fallback: "png")
            let fileName = "\(index)\(titlePart).\(ext)"
            let fileURL = comicFolder.appendingPathComponent(fileName)

            if !overwrite && fileManager.fileExists(atPath: fileURL.path) {
                return .init(imageID: image.id, fileURLString: fileURL.absoluteString, coverData: nil, wrote: false)
            }

            try data.write(to: fileURL, options: [])
            let coverData = (page.comic.coverImage == nil) ? data : nil
            return .init(imageID: image.id, fileURLString: fileURL.absoluteString, coverData: coverData, wrote: true)
        }

        // Network image path
        guard let imageURL = URL(string: image.imageURL) else { return .init(imageID: image.id, fileURLString: "", coverData: nil, wrote: false) }
        do {
            let (tempURL, response) = try await http.downloadToTemp(url: imageURL, referer: refererURL)
            guard (200..<300).contains(response.statusCode) else {
                try? fileManager.removeItem(at: tempURL)
                return .init(imageID: image.id, fileURLString: "", coverData: nil, wrote: false)
            }
            let contentType = response.value(forHTTPHeaderField: "Content-Type")
            let ext = fileExtension(contentType: contentType, urlExtension: imageURL.pathExtension, fallback: "png")

            let fileName = "\(index)\(titlePart).\(ext)"
            let fileURL = comicFolder.appendingPathComponent(fileName)

            defer { try? fileManager.removeItem(at: tempURL) }

            if !overwrite && fileManager.fileExists(atPath: fileURL.path) {
                return .init(imageID: image.id, fileURLString: fileURL.absoluteString, coverData: nil, wrote: false)
            }
            if overwrite && fileManager.fileExists(atPath: fileURL.path) { try? fileManager.removeItem(at: fileURL) }

            try fileManager.moveItem(at: tempURL, to: fileURL)
            let coverData = (page.comic.coverImage == nil) ? (try? Data(contentsOf: fileURL)) : nil
            return .init(imageID: image.id, fileURLString: fileURL.absoluteString, coverData: coverData, wrote: true)
        } catch let clientError as HTTPClientError {
            if case .cancelled = clientError { return .init(imageID: image.id, fileURLString: "", coverData: nil, wrote: false) }
            throw clientError
        }
    }

    func downloadImages(
        for comic: Comic,
        to folder: URL,
        context: ModelContext,
        overwrite: Bool = false
    ) async throws -> Int {
        let fileManager = FileManager.default
        let comicFolder = folder.appendingPathComponent(comic.name.sanitizedForFileName())

        if !fileManager.fileExists(atPath: comicFolder.path) {
            try fileManager.createDirectory(at: comicFolder, withIntermediateDirectories: true)
        }

        // Precompute page-based indexing: group by pageURL for group counts and per-image positions
        let allPagesSorted = comic.pages.sorted { $0.index < $1.index }
        var groupsByURL: [String: [ComicPage]] = [:]
        for p in allPagesSorted { groupsByURL[p.pageURL, default: []].append(p) }

        // Group count per URL (number of images per pageURL across all pages)
        let groupCountByURL: [String: Int] = {
            var dict: [String: Int] = [:]
            for (pageURL, pages) in groupsByURL {
                let count = pages.reduce(0) { $0 + $1.images.count }
                dict[pageURL] = count
            }
            return dict
        }()

        // Flatten all (page,image) pairs
        let allPairs: [(ComicPage, ComicImage)] = comic.pages.flatMap { page in
            page.images.map { (page, $0) }
        }

        var imageByID: [UUID: ComicImage] = [:]
        for (_, img) in allPairs { imageByID[img.id] = img }

        // Position map is 1-based position of each (pageURL,imageURL) within its group (ordered by page.index then image.index)
        var positionByCompositeKey: [String: Int] = [:]
        for (_, pages) in groupsByURL {
            let orderedPairs = pages
                .sorted { $0.index < $1.index }
                .flatMap { page in
                    page.images
                        .sorted { $0.index < $1.index }
                        .map { (page, $0) }
                }
            for (i, pair) in orderedPairs.enumerated() {
                let (page, image) = pair
                positionByCompositeKey["\(page.pageURL)|\(image.imageURL)"] = i + 1
            }
        }

        let availablePairs = allPairs.filter { pair in
            let (_, image) = pair
            return image.downloadPath.isEmpty || !fileManager.fileExists(atPath: image.downloadPath)
        }.sorted { lhs, rhs in
            let (lp, li) = lhs
            let (rp, ri) = rhs
            if lp.index != rp.index { return lp.index < rp.index }
            return li.index < ri.index
        }

        var filesWritten = 0
        let maxConcurrent = 6 // Be nice to remote servers

        try await withThrowingTaskGroup(of: DownloadResult.self) { group in
            var iterator = availablePairs.makeIterator()

            // Helper to enqueue the next download task if available
            func enqueueNext() {
                guard let (page, image) = iterator.next() else { return }
                let baseIndex = page.index
                let groupCount = groupCountByURL[page.pageURL] ?? 1
                let compositeKey = "\(page.pageURL)|\(image.imageURL)"
                let subNumber = positionByCompositeKey[compositeKey]
                let naming = PageNamingContext(baseIndex: baseIndex, groupCount: groupCount, subNumber: subNumber)
                group.addTask {
                    try await downloadAsset(
                        page: page,
                        image: image,
                        comicFolder: comicFolder,
                        overwrite: overwrite,
                        naming: naming
                    )
                }
            }

            // Helper to apply a finished result to the model and persist periodically
            func processResult(_ result: DownloadResult) throws {
                if result.wrote { filesWritten += 1 }
                if let imageRef = imageByID[result.imageID] {
                    imageRef.downloadPath = result.fileURLString
                    if let cover = result.coverData, imageRef.comicPage.comic.coverImage == nil {
                        imageRef.comicPage.comic.coverImage = cover
                    }
                }
                // Periodic persistence to avoid losing progress on large batches
                if result.wrote && (filesWritten % 50 == 0) {
                    try context.save()
                }
            }

            // Seed initial tasks up to the concurrency limit
            for _ in 0..<min(maxConcurrent, availablePairs.count) { enqueueNext() }

            // Drain tasks; enqueue one-for-one to maintain the window
            while let result = try await group.next() {
                try processResult(result)
                enqueueNext()
            }
        }

        try context.save()

        return filesWritten
    }
}

// MARK: - Download Helpers
private struct PageNamingContext {
    let baseIndex: Int
    let groupCount: Int
    let subNumber: Int?

    let formattedIndex: String

    nonisolated init(baseIndex: Int, groupCount: Int, subNumber: Int?) {
        self.baseIndex = baseIndex
        self.groupCount = groupCount
        self.subNumber = subNumber

        // Zero-pad baseIndex to width 5 without using String(format:)
        let baseString = String(baseIndex)
        let paddingCount = max(0, 5 - baseString.count)
        var formattedIndex = String(repeating: "0", count: paddingCount) + baseString

        if groupCount > 1 {
            let postSuffix = String(max(1, subNumber ?? 1))
            formattedIndex += ("-" + String(repeating: "0", count: max(0, postSuffix.count - 1)) + postSuffix)
        }
        self.formattedIndex = formattedIndex
    }
}
