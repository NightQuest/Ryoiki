//
//  ComicManager+Downloading.swift
//  Ryoiki
//

import Foundation
import SwiftData

// MARK: - Image Downloading
extension ComicManager {

    private struct MissingScanContext {
        let comicID: UUID
        let comicFolder: URL
        let fileManager: FileManager
        let existingFileSet: Set<String>
        let resolvedPath: (String) -> String?
    }

    private func findMissingOnDiskImages(
        context: ModelContext,
        scan: MissingScanContext
    ) throws -> [ComicImage] {
        var missing: [ComicImage] = []
        var fetchOffset = 0
        let fetchLimit = 1000
        while true {
            try Task.checkCancellation()
            let id = scan.comicID
            var desc = FetchDescriptor<ComicImage>(
                predicate: #Predicate { $0.comicPage.comic.id == id && $0.downloadPath != "" },
                sortBy: [
                    SortDescriptor(\.comicPage.index),
                    SortDescriptor(\.index)
                ]
            )
            desc.fetchLimit = fetchLimit
            desc.fetchOffset = fetchOffset
            let batch: [ComicImage] = try context.fetch(desc)
            if batch.isEmpty { break }

            for img in batch {
                guard let fsPath = scan.resolvedPath(img.downloadPath) else {
                    missing.append(img)
                    continue
                }
                if fsPath.hasPrefix(scan.comicFolder.path) {
                    if !scan.existingFileSet.contains(fsPath) { missing.append(img) }
                } else {
                    if !scan.fileManager.fileExists(atPath: fsPath) { missing.append(img) }
                }
            }

            fetchOffset += batch.count
        }
        return missing
    }

    private struct DownloadResult {
        let imageID: UUID
        let fileURLString: String
        let filePath: String
        let coverData: Data?
        let wrote: Bool
        let didDownload: Bool
    }

    private struct DownloadInput: Sendable {
        let imageID: UUID
        let pageURL: String
        let pageIndex: Int
        let pageTitle: String
        let imageURL: String
        let needsCover: Bool
    }

    private func downloadAsset(
        input: DownloadInput,
        comicFolder: URL,
        overwrite: Bool,
        naming: PageNamingContext
    ) async throws -> DownloadResult {
        let fileManager = FileManager.default
        guard let refererURL = URL(string: input.pageURL) else {
            return .init(imageID: input.imageID,
                         fileURLString: "",
                         filePath: "",
                         coverData: nil,
                         wrote: false,
                         didDownload: false)
        }

        let index = naming.formattedIndex
        let titlePart: String = input.pageTitle.isEmpty ? "" : " " + input.pageTitle.sanitizedForFileName()

        // Data URL path
        if input.imageURL.hasPrefix("data:") {
            guard let (mediatype, data) = decodeDataURL(input.imageURL) else {
                return .init(imageID: input.imageID,
                             fileURLString: "",
                             filePath: "",
                             coverData: nil,
                             wrote: false,
                             didDownload: false)
            }
            let ext = fileExtension(contentType: mediatype, urlExtension: nil, fallback: "png")
            let fileName = "\(index)\(titlePart).\(ext)"
            let fileURL = comicFolder.appendingPathComponent(fileName)

            if !overwrite && fileManager.fileExists(atPath: fileURL.path) {
                return .init(imageID: input.imageID,
                             fileURLString: fileURL.absoluteString,
                             filePath: fileURL.path,
                             coverData: nil,
                             wrote: false,
                             didDownload: false)
            }

            try data.write(to: fileURL, options: [])
            let coverData = input.needsCover ? data : nil
            return .init(imageID: input.imageID,
                         fileURLString: fileURL.absoluteString,
                         filePath: fileURL.path,
                         coverData: coverData,
                         wrote: true,
                         didDownload: true)
        }

        // Network image path
        guard let imageURL = URL(string: input.imageURL) else {
            return .init(imageID: input.imageID,
                         fileURLString: "",
                         filePath: "",
                         coverData: nil,
                         wrote: false,
                         didDownload: false)
        }
        do {
            let (tempURL, response) = try await http.downloadToTemp(url: imageURL, referer: refererURL)
            guard (200..<300).contains(response.statusCode) else {
                try? fileManager.removeItem(at: tempURL)
                return .init(imageID: input.imageID,
                             fileURLString: "",
                             filePath: "",
                             coverData: nil,
                             wrote: false,
                             didDownload: false)
            }
            let contentType = response.value(forHTTPHeaderField: "Content-Type")
            let ext = fileExtension(contentType: contentType, urlExtension: imageURL.pathExtension, fallback: "png")

            let fileName = "\(index)\(titlePart).\(ext)"
            let fileURL = comicFolder.appendingPathComponent(fileName)

            defer { try? fileManager.removeItem(at: tempURL) }

            if !overwrite && fileManager.fileExists(atPath: fileURL.path) {
                return .init(imageID: input.imageID,
                             fileURLString: fileURL.absoluteString,
                             filePath: fileURL.path,
                             coverData: nil,
                             wrote: false,
                             didDownload: false)
            }
            if overwrite && fileManager.fileExists(atPath: fileURL.path) { try? fileManager.removeItem(at: fileURL) }

            try fileManager.moveItem(at: tempURL, to: fileURL)
            let coverData = input.needsCover ? (try? Data(contentsOf: fileURL)) : nil
            return .init(imageID: input.imageID,
                         fileURLString: fileURL.absoluteString,
                         filePath: fileURL.path,
                         coverData: coverData,
                         wrote: true,
                         didDownload: true)
        } catch let clientError as HTTPClientError {
            if case .cancelled = clientError {
                return .init(imageID: input.imageID,
                             fileURLString: "",
                             filePath: "",
                             coverData: nil,
                             wrote: false,
                             didDownload: false)
            }
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

        await CommitGate.shared.waitIfPaused()

        // Helper to resolve a stored downloadPath (which may be a URL string or plain path) into a filesystem path
        func resolvedFileSystemPath(from storedPath: String) -> String? {
            guard !storedPath.isEmpty else { return nil }
            if let url = URL(string: storedPath), url.scheme != nil {
                // If scheme is present, prefer the URL's path component
                return url.path
            } else {
                return storedPath
            }
        }

        // Precompute existing files in the target folder for fast membership checks
        let existingFileSet: Set<String> = {
            if let names = try? fileManager.contentsOfDirectory(atPath: comicFolder.path) {
                return Set(names.map { comicFolder.appendingPathComponent($0).path })
            }
            return []
        }()

        // Build a minimal working set of images to download using background-friendly fetches
        let comicID = comic.id

        // 1) Images that have not been downloaded yet (downloadPath == "")
        let freshImages: [ComicImage] = try context.fetch(
            FetchDescriptor<ComicImage>(
                predicate: #Predicate { $0.comicPage.comic.id == comicID && $0.downloadPath == "" },
                sortBy: [
                    SortDescriptor(\.comicPage.index),
                    SortDescriptor(\.index)
                ]
            )
        )

        // 2) Images that claim to be downloaded but whose file is missing on disk
        //    Fetch in chunks to reduce peak memory, and use precomputed directory contents for fast checks.
        let scanCtx = MissingScanContext(
            comicID: comicID,
            comicFolder: comicFolder,
            fileManager: fileManager,
            existingFileSet: existingFileSet,
            resolvedPath: { resolvedFileSystemPath(from: $0) }
        )
        let missingOnDisk = try findMissingOnDiskImages(context: context, scan: scanCtx)

        // Combine, de-duplicating by id
        var byID: [UUID: ComicImage] = [:]
        for i in freshImages { byID[i.id] = i }
        for i in missingOnDisk { byID[i.id] = i }

        // Sort final list in deterministic reading order (page.index, image.index)
        let imagesToProcess: [ComicImage] = byID.values.sorted { lhs, rhs in
            let lp = lhs.comicPage.index
            let rp = rhs.comicPage.index
            if lp != rp { return lp < rp }
            return lhs.index < rhs.index
        }

        try Task.checkCancellation()

        var filesWritten = 0
        let userMax = UserDefaults.standard.integer(forKey: .settingsDownloadMaxConcurrent)
        let maxConcurrent = max(1, min(userMax == 0 ? 10 : userMax, 24)) // default 10, clamp 1...24

        // Fast exit if nothing to do
        if imagesToProcess.isEmpty {
            try context.save()
            return filesWritten
        }

        try Task.checkCancellation()
        try await withThrowingTaskGroup(of: DownloadResult.self) { group in
            var iterator = imagesToProcess.makeIterator()

            // Helper to enqueue the next download task if available
            func enqueueNext() {
                guard let image = iterator.next() else { return }
                let page = image.comicPage

                // Compute naming using per-page ordering to avoid global precomputation
                let baseIndex = page.index
                let groupCount = page.images.count
                let subNumber = (groupCount > 1) ? (image.index + 1) : nil
                let naming = PageNamingContext(baseIndex: baseIndex, groupCount: groupCount, subNumber: subNumber)

                let input = DownloadInput(
                    imageID: image.id,
                    pageURL: page.pageURL,
                    pageIndex: page.index,
                    pageTitle: page.title,
                    imageURL: image.imageURL,
                    needsCover: (page.comic.coverImage == nil)
                )

                group.addTask {
                    try Task.checkCancellation()
                    return try await downloadAsset(
                        input: input,
                        comicFolder: comicFolder,
                        overwrite: overwrite,
                        naming: naming
                    )
                }
            }

            // Helper to apply a finished result to the model and persist periodically
            func processResult(_ result: DownloadResult) async throws {
                if result.wrote { filesWritten += 1 }
                if let imageRef = byID[result.imageID] {
                    imageRef.downloadPath = result.fileURLString

                    let comicRef = imageRef.comicPage.comic
                    if result.didDownload {
                        comicRef.downloadedImageCount += 1
                    }

                    if let cover = result.coverData, comicRef.coverImage == nil {
                        comicRef.coverImage = cover
                    }
                    if comicRef.coverFilePath.isEmpty {
                        comicRef.coverFilePath = result.filePath
                    }
                }
                // Periodic persistence to avoid losing progress on large batches
                if result.wrote && (filesWritten % 50 == 0) {
                    await CommitGate.shared.pause()
                    defer { Task { await CommitGate.shared.resume() } }
                    try context.save()
                }
            }

            // Seed initial tasks up to the concurrency limit
            for _ in 0..<min(maxConcurrent, imagesToProcess.count) { enqueueNext() }

            // Drain tasks; enqueue one-for-one to maintain the window
            while let result = try await group.next() {
                await CommitGate.shared.waitIfPaused()
                try Task.checkCancellation()
                try await processResult(result)
                enqueueNext()
            }
        }

        await CommitGate.shared.pause()
        defer { Task { await CommitGate.shared.resume() } }
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
        let basePadded = String(repeating: "0", count: paddingCount) + baseString

        if groupCount > 1 {
            let sub = max(1, subNumber ?? 1)
            self.formattedIndex = "\(basePadded)-\(sub)"
        } else {
            self.formattedIndex = basePadded
        }
    }
}
