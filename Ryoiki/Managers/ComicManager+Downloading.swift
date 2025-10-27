//
//  ComicManager+Downloading.swift
//  Ryoiki
//

import Foundation
import SwiftData

// MARK: - Image Downloading
extension ComicManager {
    // Heavy I/O is performed off-main; model writes hop to main actor.
    func downloadImages(
        for comic: Comic,
        to folder: URL,
        context: ModelContext,
        overwrite: Bool = false
    ) async throws -> Int {
        let fileManager = FileManager.default
        let comicFolder = folder.appendingPathComponent(sanitizeFilename(comic.name))

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

        // Parallelize downloads with limited concurrency. Model writes hop to MainActor in handlePageDownload.
        try await withThrowingTaskGroup(of: Bool.self) { group in
            var iterator = availablePairs.makeIterator()

            // Seed initial tasks up to the concurrency limit
            for _ in 0..<min(maxConcurrent, availablePairs.count) {
                guard let (page, image) = iterator.next() else { break }
                let baseIndex = page.index
                let groupCount = groupCountByURL[page.pageURL] ?? 1
                let compositeKey = "\(page.pageURL)|\(image.imageURL)"
                let subNumber = positionByCompositeKey[compositeKey]
                let naming = PageNamingContext(baseIndex: baseIndex, groupCount: groupCount, subNumber: subNumber)

                group.addTask {
                    try await handlePageDownload(
                        page: page,
                        image: image,
                        comicFolder: comicFolder,
                        overwrite: overwrite,
                        naming: naming
                    )
                }
            }

            // For each finished task, enqueue the next pair, maintaining the concurrency window
            while let wrote = try await group.next() {
                if wrote { filesWritten += 1 }

                if let (page, image) = iterator.next() {
                    let baseIndex = page.index
                    let groupCount = groupCountByURL[page.pageURL] ?? 1
                    let compositeKey = "\(page.pageURL)|\(image.imageURL)"
                    let subNumber = positionByCompositeKey[compositeKey]
                    let naming = PageNamingContext(baseIndex: baseIndex, groupCount: groupCount, subNumber: subNumber)

                    group.addTask {
                        try await handlePageDownload(
                            page: page,
                            image: image,
                            comicFolder: comicFolder,
                            overwrite: overwrite,
                            naming: naming
                        )
                    }
                }
            }
        }

        return filesWritten
    }
}

// MARK: - Download Helpers
private extension ComicManager {
    struct PageNamingContext {
        let baseIndex: Int
        let groupCount: Int
        let subNumber: Int?

        let formattedIndex: String

        init(baseIndex: Int, groupCount: Int, subNumber: Int?) {
            self.baseIndex = baseIndex
            self.groupCount = groupCount
            self.subNumber = subNumber

            var formattedIndex = String(format: "%05d", baseIndex)
            if groupCount > 1 {
                let postSuffix = String(max(1, subNumber ?? 1))

                formattedIndex += ("-" +
                                  String(repeating: "0", count: postSuffix.count - 1) +
                                  postSuffix)

            }
            self.formattedIndex = formattedIndex
        }
    }

    // This updates model properties; must be on main actor when touching models.
    func handlePageDownload(page: ComicPage,
                            image: ComicImage,
                            comicFolder: URL,
                            overwrite: Bool,
                            naming: PageNamingContext) async throws -> Bool {
        let fileManager = FileManager.default

        guard let refererURL = URL(string: page.pageURL) else { return false }

        let index = naming.formattedIndex
        let titlePart: String = page.title.isEmpty ? "" : " - " + sanitizeFilename(page.title)

        // Data URL path
        if image.imageURL.hasPrefix("data:") {
            guard let (mediatype, data) = decodeDataURL(image.imageURL) else { return false }
            let ext = fileExtension(contentType: mediatype, urlExtension: nil, fallback: "png")
            let fileName = "\(index)\(titlePart).\(ext)"
            let fileURL = comicFolder.appendingPathComponent(fileName)

            if !overwrite && fileManager.fileExists(atPath: fileURL.path) { return true }

            try data.write(to: fileURL, options: [])
            await MainActor.run { image.downloadPath = fileURL.absoluteString }
            await MainActor.run {
                if page.comic.coverImage == nil, let data = try? Data(contentsOf: fileURL) {
                    page.comic.coverImage = data
                }
            }
            return true
        }

        // Network image path
        guard let imageURL = URL(string: image.imageURL) else { return false }
        do {
            let (tempURL, response) = try await http.downloadToTemp(url: imageURL, referer: refererURL)
            guard (200..<300).contains(response.statusCode) else {
                try? fileManager.removeItem(at: tempURL)
                return false
            }
            let contentType = response.value(forHTTPHeaderField: "Content-Type")
            let ext = fileExtension(contentType: contentType, urlExtension: imageURL.pathExtension, fallback: "png")

            let fileName = "\(index)\(titlePart).\(ext)"
            let fileURL = comicFolder.appendingPathComponent(fileName)

            defer { try? fileManager.removeItem(at: tempURL) }

            if !overwrite && fileManager.fileExists(atPath: fileURL.path) { return true }
            if overwrite && fileManager.fileExists(atPath: fileURL.path) { try? fileManager.removeItem(at: fileURL) }

            try fileManager.moveItem(at: tempURL, to: fileURL)
            await MainActor.run { image.downloadPath = fileURL.absoluteString }
            await MainActor.run {
                if page.comic.coverImage == nil, let data = try? Data(contentsOf: fileURL) {
                    page.comic.coverImage = data
                }
            }
            return true
        } catch let clientError as HTTPClientError {
            // Swallow cancellations silently; propagate other errors
            if case .cancelled = clientError { return false }
            throw clientError
        }
    }
}
