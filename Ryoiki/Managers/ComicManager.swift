//
//  ComicManager.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-21.
//

import Foundation
import SwiftSoup
import SwiftData

struct ComicManager: Sendable {
    private let rateLimiter: RateLimiter

    enum Error: Swift.Error {
        case network(Swift.Error)
        case badStatus(Int)
        case parse
        case invalidBaseURL
        case missingSelector(String)
        case cancelled
    }

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15"
    private let session: URLSession

    init(session: URLSession = .shared, rateLimiter: RateLimiter = .shared) {
        self.session = session
        self.rateLimiter = rateLimiter
    }

    // MARK: - Networking

    private func makeRequest(url: URL, method: String, referer: URL?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        return request
    }

    private func request(url: URL, method: String, referer: URL?) async throws -> (Data, HTTPURLResponse) {
        await rateLimiter.acquire(for: url)
        let request = makeRequest(url: url, method: method, referer: referer)
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.network(URLError(.badServerResponse))
            }
            return (data, httpResponse)
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// Maps any thrown error into a `ComicManager.Error`, preserving cancellation semantics.
    private func mapNetworkError(_ error: Swift.Error) -> ComicManager.Error {
        if error is CancellationError { return .cancelled }
        return .network(error)
    }

    /// Downloads a resource to a temporary file using URLSession.download(for:), applying headers.
    private func downloadToTemp(url: URL, referer: URL?) async throws -> (URL, HTTPURLResponse) {
        await rateLimiter.acquire(for: url)
        let request = makeRequest(url: url, method: "GET", referer: referer)
        do {
            let (tempURL, response) = try await session.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.network(URLError(.badServerResponse))
            }
            return (tempURL, httpResponse)
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// Loads an HTML document as a UTF-8 string using a GET request, applying the configured User-Agent and optional Referer.
    func html(from url: URL, referer: URL? = nil) async throws -> String {
        do {
            let (data, response) = try await request(url: url, method: "GET", referer: referer)
            guard (200..<300).contains(response.statusCode) else {
                throw Error.badStatus(response.statusCode)
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw Error.parse // keep domain-specific error, but decoding failed
            }
            return html
        } catch let scraperError as ComicManager.Error {
            // Forward scraper errors as-is (including .cancelled)
            throw scraperError
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// Performs a HEAD request and returns the status code and Content-Type header if present.
    func head(_ url: URL, referer: URL? = nil) async throws -> (status: Int, contentType: String?) {
        do {
            let (_, response) = try await request(url: url, method: "HEAD", referer: referer)
            let contentType = response.value(forHTTPHeaderField: "Content-Type")
            return (response.statusCode, contentType)
        } catch let scraperError as ComicManager.Error {
            // Forward scraper errors as-is (including .cancelled)
            throw scraperError
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// Loads raw data using a GET request, applying the configured User-Agent and optional Referer.
    func getData(_ url: URL, referer: URL? = nil) async throws -> Data {
        do {
            let (data, response) = try await request(url: url, method: "GET", referer: referer)
            guard (200..<300).contains(response.statusCode) else {
                throw Error.badStatus(response.statusCode)
            }
            return data
        } catch let scraperError as ComicManager.Error {
            // Forward scraper errors as-is (including .cancelled)
            throw scraperError
        } catch {
            throw mapNetworkError(error)
        }
    }

    func fetchPages(
        for comic: Comic,
        context: ModelContext,
        maxPages: Int? = nil
    ) async throws -> Int {
        // Snapshot model-derived values that require main-actor access once up front
        let firstPageURL: URL = try await MainActor.run { () -> URL in
            let firstPage = comic.pages.last?.pageURL ?? comic.firstPageURL
            guard let firstPageTrimmed = firstPage.trimmedNilIfEmpty,
                  let url = URL(string: firstPageTrimmed) else {
                throw Error.invalidBaseURL
            }
            return url
        }

        let selectorNext = comic.selectorNext
        let selectorImage = comic.selectorImage
        let selectorTitle = comic.selectorTitle

        if selectorImage.isEmpty {
            throw Error.missingSelector("selectorImage")
        }

        // Build a fast lookup of existing (pageURL|imageURL) pairs to avoid O(n) scans on main actor
        var existingPairKeys: Set<String> = await MainActor.run {
            Set(comic.pages.map { "\($0.pageURL)|\($0.imageURL)" })
        }

        // Find current maximum index in existing pages (main-actor snapshot once)
        var currentMaxIndex: Int = await MainActor.run {
            comic.pages.max(by: { $0.index < $1.index })?.index ?? -1
        }

        var visitedURLs = Set<String>()
        var pagesAdded = 0

        var currentURL = firstPageURL
        var previousURL: URL?

        var pendingPages: [CMTypes.PageSpec] = []

        var preparedSinceLastCommit = 0
        let commitThreshold = 5 // commit every N prepared pages

        @inline(__always)
        func shouldStop(maxPages: Int?, pagesAdded: Int) -> Bool {
            if let max = maxPages, pagesAdded >= max { return true }
            return false
        }

        @MainActor
        func applyPendingPages() throws {
            guard !pendingPages.isEmpty else { return }
            for spec in pendingPages {
                let page = ComicPage(
                    comic: comic,
                    index: spec.index,
                    title: spec.title,
                    pageURL: spec.pageURL,
                    imageURL: spec.imageURL
                )
                context.insert(page)
            }
            try context.save()
        }

        func finalizeIfNeeded(force: Bool = false) async throws {
            if force || preparedSinceLastCommit >= commitThreshold {
                try await MainActor.run {
                    try applyPendingPages()
                }
                pendingPages.removeAll(keepingCapacity: true)
                preparedSinceLastCommit = 0
                await Task.yield()
            }
        }

        func nextURL(from current: URL, parsed: CMTypes.ParseResult, selectorNext: String, visited: Set<String>) -> URL? {
            advance(from: current, using: parsed.doc, selectorNext: selectorNext, visited: visited)
        }

        // Ensure we always try to commit pending pages on function exit/cancellation
        defer {
            Task { @MainActor in
                do {
                    try applyPendingPages()
                } catch {
                    // Swallow here; caller already receives the thrown error from main body
                }
            }
        }

        while true {
            if shouldStop(maxPages: maxPages, pagesAdded: pagesAdded) { break }
            guard visitedURLs.insert(currentURL.absoluteString).inserted else { break }

            let parsed = try await fetchAndParse(
                url: currentURL,
                referer: previousURL,
                selectorTitle: selectorTitle,
                selectorImage: selectorImage
            )

            guard !parsed.imageURLs.isEmpty else { break }

            let prep: CMTypes.PreparationResult = try await MainActor.run {
                let input = CMTypes.PreparationInput(
                    currentPageURL: currentURL,
                    startingIndex: currentMaxIndex,
                    titleText: parsed.title,
                    maxPages: maxPages.map { $0 - pagesAdded },
                    existingPairKeys: existingPairKeys
                )
                return try preparePagesWithoutInserting(
                    from: parsed.imageURLs,
                    input: input
                )
            }

            existingPairKeys = prep.updatedKeys
            pendingPages.append(contentsOf: prep.prepared)

            pagesAdded += prep.result.inserted
            currentMaxIndex = prep.result.newStartingIndex
            if prep.result.didReachMax { try await finalizeIfNeeded(force: true); break }

            preparedSinceLastCommit += prep.prepared.count
            try await finalizeIfNeeded()

            previousURL = currentURL

            if shouldStop(maxPages: maxPages, pagesAdded: pagesAdded) { try await finalizeIfNeeded(force: true); break }
            guard let next = nextURL(from: currentURL,
                                     parsed: parsed,
                                     selectorNext: selectorNext,
                                     visited: visitedURLs) else { try await finalizeIfNeeded(force: true); break }
            currentURL = next
        }

        // Normal completion path: ensure everything is committed
        try await finalizeIfNeeded(force: true)
        return pagesAdded
    }

    // Heavy I/O is performed off-main; model writes hop to main actor.
    func downloadImages(
        for comic: Comic,
        to folder: URL,
        context: ModelContext,
        overwrite: Bool = false
    ) async throws -> Int {
        // This method interacts with UI-bound model properties (@MainActor).
        // Heavy file IO occurs here; consider off-main-thread execution in future for performance.
        let fileManager = FileManager.default
        let comicFolder = folder.appendingPathComponent(sanitizeFilename(comic.name))

        if !fileManager.fileExists(atPath: comicFolder.path) {
            try fileManager.createDirectory(at: comicFolder, withIntermediateDirectories: true)
        }

        // Precompute page-based indexing: group by pageURL to assign a shared base index and per-image position
        let allPagesSorted = comic.pages.sorted { $0.index < $1.index }
        var groupsByURL: [String: [ComicPage]] = [:]
        for p in allPagesSorted {
            groupsByURL[p.pageURL, default: []].append(p)
        }
        // Base index is the smallest index in the group
        let baseIndexByURL: [String: Int] = groupsByURL.mapValues { group in
            group.map { $0.index }.min() ?? 0
        }
        // Group count per URL
        let groupCountByURL: [String: Int] = groupsByURL.mapValues { $0.count }
        // Position map is 1-based position of each (pageURL,imageURL) within its group (ordered by ComicPage.index)
        var positionByCompositeKey: [String: Int] = [:]
        for (url, group) in groupsByURL {
            let ordered = group.sorted { $0.index < $1.index }
            for (i, p) in ordered.enumerated() {
                let key = "\(url)|\(p.imageURL)"
                positionByCompositeKey[key] = i + 1
            }
        }

        let availablePages = comic.pages
            .filter { page in
                page.downloadPath.isEmpty ||
                !fileManager.fileExists(atPath: page.downloadPath)
            }
            .sorted { $0.index < $1.index }

        var filesWritten = 0

        let maxConcurrent = 6 // Be nice to remote servers

        // Parallelize downloads with limited concurrency. Model writes hop to MainActor in handlePageDownload.
        try await withThrowingTaskGroup(of: Bool.self) { group in
            var iterator = availablePages.makeIterator()

            // Seed initial tasks up to the concurrency limit
            for _ in 0..<min(maxConcurrent, availablePages.count) {
                guard let page = iterator.next() else { break }
                let baseIndex = baseIndexByURL[page.pageURL] ?? page.index
                let groupCount = groupCountByURL[page.pageURL] ?? 1
                let compositeKey = "\(page.pageURL)|\(page.imageURL)"
                let subNumber = positionByCompositeKey[compositeKey]
                let naming = PageNamingContext(baseIndex: baseIndex, groupCount: groupCount, subNumber: subNumber)

                group.addTask {
                    try await handlePageDownload(
                        page: page,
                        comicFolder: comicFolder,
                        overwrite: overwrite,
                        naming: naming
                    )
                }
            }

            // For each finished task, enqueue the next page, maintaining the concurrency window
            while let wrote = try await group.next() {
                if wrote { filesWritten += 1 }

                if let page = iterator.next() {
                    let baseIndex = baseIndexByURL[page.pageURL] ?? page.index
                    let groupCount = groupCountByURL[page.pageURL] ?? 1
                    let compositeKey = "\(page.pageURL)|\(page.imageURL)"
                    let subNumber = positionByCompositeKey[compositeKey]
                    let naming = PageNamingContext(baseIndex: baseIndex, groupCount: groupCount, subNumber: subNumber)

                    group.addTask {
                        try await handlePageDownload(
                            page: page,
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

    private struct PageNamingContext {
        let baseIndex: Int
        let groupCount: Int
        let subNumber: Int?
    }

    // This updates model properties; must be on main actor, but now called off-main.
    private func handlePageDownload(page: ComicPage, comicFolder: URL, overwrite: Bool, naming: PageNamingContext) async throws -> Bool {
        let fileManager = FileManager.default

        guard let pageURL = URL(string: page.pageURL) else {
            return false
        }

        let indexPadded = String(format: "%05d", naming.baseIndex)
        let suffix = naming.groupCount > 1 ? "-\(max(1, naming.subNumber ?? 1))" : ""
        let indexWithSuffix = indexPadded + suffix
        let titlePart: String = page.title.isEmpty ? "" : " - " + sanitizeFilename(page.title)

        // Data URL path
        if page.imageURL.hasPrefix("data:") {
            guard let (mediatype, data) = decodeDataURL(page.imageURL) else { return false }
            let ext = fileExtension(contentType: mediatype, urlExtension: nil, fallback: "png")
            let fileName = "\(indexWithSuffix)\(titlePart).\(ext)"
            let fileURL = comicFolder.appendingPathComponent(fileName)

            if !overwrite && fileManager.fileExists(atPath: fileURL.path) {
                return true
            }

            try data.write(to: fileURL, options: .atomic)
            await MainActor.run {
                page.downloadPath = fileURL.absoluteString
            }
            return true
        }

        // Network image path
        guard let imageURL = URL(string: page.imageURL) else { return false }
        let (tempURL, response) = try await downloadToTemp(url: imageURL, referer: pageURL)
        guard (200..<300).contains(response.statusCode) else {
            try? fileManager.removeItem(at: tempURL)
            return false
        }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        let ext = fileExtension(contentType: contentType, urlExtension: imageURL.pathExtension, fallback: "png")

        let fileName = "\(indexWithSuffix)\(titlePart).\(ext)"
        let fileURL = comicFolder.appendingPathComponent(fileName)

        defer { try? fileManager.removeItem(at: tempURL) }

        if !overwrite && fileManager.fileExists(atPath: fileURL.path) {
            return true
        }

        if overwrite && fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }

        try fileManager.moveItem(at: tempURL, to: fileURL)
        await MainActor.run {
            page.downloadPath = fileURL.absoluteString
        }
        return true
    }

    // MARK: - Navigation

    private func nextLink(in doc: Document, selector: String, baseURL: URL) -> URL? {
        guard !selector.isEmpty else { return nil }
        if let href = try? doc.select(selector).first()?.attr("href") {
            return resolveURL(href, base: baseURL)
        }
        return nil
    }

    // MARK: - Retry

    private func fetchHTMLWithRetry(from url: URL, referer: URL?, attempts: Int = 3) async throws -> String {
        var lastError: Swift.Error?
        for attempt in 0..<max(1, attempts) {
            do {
                return try await html(from: url, referer: referer)
            } catch {
                // Do not retry on cancellation
                if error is CancellationError {
                    throw error
                }
                if let scraperError = error as? ComicManager.Error, case .cancelled = scraperError {
                    throw scraperError
                }
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? ComicManager.Error.network(NSError(domain: "Unknown", code: -1))
    }

    private func advance(from current: URL, using doc: Document, selectorNext: String, visited: Set<String>) -> URL? {
        guard let next = nextLink(in: doc, selector: selectorNext, baseURL: current) else { return nil }
        guard !visited.contains(next.absoluteString) else { return nil }
        return next
    }

    // MARK: - Deletion

    /// Deletes the folder on disk that contains downloaded images for the given comic.
    /// The folder is assumed to be located at `baseFolder/sanitizeFilename(comic.name)`.
    /// If the folder exists, it and all of its contents will be removed.
    func deleteDownloadFolder(for comic: Comic, in baseFolder: URL) {
        let fm = FileManager.default
        let folder = baseFolder.appendingPathComponent(sanitizeFilename(comic.name))
        if fm.fileExists(atPath: folder.path) {
            try? fm.removeItem(at: folder)
        }
    }
}
