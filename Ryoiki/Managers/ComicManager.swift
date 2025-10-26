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
    private let http: HTTPClientProtocol

    enum Error: Swift.Error {
        case network(Swift.Error)
        case badStatus(Int)
        case parse
        case invalidBaseURL
        case missingSelector(String)
        case cancelled
    }

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.http = httpClient
    }

    /// Loads an HTML document as a UTF-8 string using a GET request, applying the configured User-Agent and optional Referer.
    func html(from url: URL, referer: URL? = nil) async throws -> String {
        do {
            let (data, response) = try await http.get(url, referer: referer)
            guard (200..<300).contains(response.statusCode) else {
                throw Error.badStatus(response.statusCode)
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw Error.parse
            }
            return html
        } catch let clientError as HTTPClientError {
            switch clientError {
            case .badStatus(let code): throw Error.badStatus(code)
            case .cancelled: throw CancellationError()
            case .network(let underlying): throw Error.network(underlying)
            }
        }
    }

    func head(_ url: URL, referer: URL? = nil) async throws -> HTTPURLResponse {
        do {
            return try await http.head(url, referer: referer)
        } catch let clientError as HTTPClientError {
            switch clientError {
            case .badStatus(let code): throw Error.badStatus(code)
            case .cancelled: throw CancellationError()
            case .network(let underlying): throw Error.network(underlying)
            }
        }
    }

    func getData(_ url: URL, referer: URL? = nil) async throws -> Data {
        do {
            let (data, response) = try await http.get(url, referer: referer)
            guard (200..<300).contains(response.statusCode) else {
                throw Error.badStatus(response.statusCode)
            }
            return data
        } catch let clientError as HTTPClientError {
            switch clientError {
            case .badStatus(let code): throw Error.badStatus(code)
            case .cancelled: throw CancellationError()
            case .network(let underlying): throw Error.network(underlying)
            }
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
        let existingPairKeys: Set<String> = await MainActor.run {
            Set(comic.pages.map { "\($0.pageURL)|\($0.imageURL)" })
        }

        // Find current maximum index in existing pages (main-actor snapshot once)
        let currentMaxIndex: Int = await MainActor.run {
            comic.pages.max(by: { $0.index < $1.index })?.index ?? -1
        }

        let initiallyEmpty: Bool = await MainActor.run { comic.pages.isEmpty }

        let visitedURLs = Set<String>()
        let pagesAdded = 0

        let currentURL = firstPageURL
        let previousURL: URL? = nil

        let preparedSinceLastCommit = 0
        let commitThreshold = 5 // commit every N prepared pages

        let selectors = Selectors(title: selectorTitle, image: selectorImage, next: selectorNext)

        var state = FetchState(
            didSetCoverAtFetchTime: false,
            existingPairKeys: existingPairKeys,
            currentMaxIndex: currentMaxIndex,
            visitedURLs: visitedURLs,
            pagesAdded: pagesAdded,
            currentURL: currentURL,
            previousURL: previousURL,
            pendingPages: [],
            preparedSinceLastCommit: preparedSinceLastCommit,
            commitThreshold: commitThreshold,
            initiallyEmpty: initiallyEmpty
        )

        let env = FetchEnv(comic: comic, context: context)

        // Ensure we always try to commit pending pages on function exit/cancellation
        defer {
            Task { @MainActor in
                do {
                    try self.applyPendingPages(state: &state, env: env)
                } catch { }
            }
        }

        while true {
            let result = try await stepOnce(
                maxPages: maxPages,
                selectors: selectors,
                env: env,
                state: &state
            )

            switch result {
            case .advance(let next, let newPrevious):
                state.previousURL = newPrevious
                state.currentURL = next
            case .finished:
                try await finalizeIfNeeded(state: &state,
                                           env: env,
                                           force: true)
                return state.pagesAdded
            }
        }
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
            await MainActor.run {
                if page.comic.coverImage == nil, let data = try? Data(contentsOf: fileURL) {
                    page.comic.coverImage = data
                }
            }
            return true
        }

        // Network image path
        guard let imageURL = URL(string: page.imageURL) else { return false }
        do {
            let (tempURL, response) = try await http.downloadToTemp(url: imageURL, referer: pageURL)
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
                return try await self.html(from: url, referer: referer)
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

extension ComicManager {
    struct FetchState {
        var didSetCoverAtFetchTime: Bool
        var existingPairKeys: Set<String>
        var currentMaxIndex: Int
        var visitedURLs: Set<String>
        var pagesAdded: Int
        var currentURL: URL
        var previousURL: URL?
        var pendingPages: [CMTypes.PageSpec]
        var preparedSinceLastCommit: Int
        let commitThreshold: Int
        let initiallyEmpty: Bool
    }

    struct Selectors {
        let title: String
        let image: String
        let next: String
    }

    struct FetchEnv {
        let comic: Comic
        let context: ModelContext
    }

    enum StepOutcome {
        case advance(to: URL, previous: URL?)
        case finished
    }

    @inline(__always)
    func shouldStop(maxPages: Int?, pagesAdded: Int) -> Bool {
        if let max = maxPages, pagesAdded >= max { return true }
        return false
    }

    @MainActor
    func applyPendingPages(state: inout FetchState, env: FetchEnv) throws {
        guard !state.pendingPages.isEmpty else { return }
        for spec in state.pendingPages {
            let page = ComicPage(
                comic: env.comic,
                index: spec.index,
                title: spec.title,
                pageURL: spec.pageURL,
                imageURL: spec.imageURL
            )
            env.context.insert(page)
        }
        try env.context.save()
        state.pendingPages.removeAll(keepingCapacity: true)
    }

    func finalizeIfNeeded(state: inout FetchState,
                          env: FetchEnv,
                          force: Bool = false) async throws {
        if force || state.preparedSinceLastCommit >= state.commitThreshold {
            try await MainActor.run {
                try applyPendingPages(state: &state, env: env)
            }
            state.preparedSinceLastCommit = 0
            await Task.yield()
        }
    }

    func maybeSetCover(from parsed: CMTypes.ParseResult,
                       referer: URL,
                       env: FetchEnv,
                       state: inout FetchState) async {
        guard state.initiallyEmpty, !state.didSetCoverAtFetchTime, let firstImageURL = parsed.imageURLs.first else { return }
        do {
            let data = try await getData(firstImageURL, referer: referer)
            await MainActor.run {
                if env.comic.coverImage == nil {
                    env.comic.coverImage = data
                    try? env.context.save()
                }
            }
            state.didSetCoverAtFetchTime = true
        } catch { }
    }

    func prepareBatch(from parsed: CMTypes.ParseResult,
                      at url: URL,
                      maxPages: Int?,
                      state: FetchState) async throws -> CMTypes.PreparationResult {
        try await MainActor.run {
            let input = CMTypes.PreparationInput(
                currentPageURL: url,
                startingIndex: state.currentMaxIndex,
                titleText: parsed.title,
                maxPages: maxPages.map { $0 - state.pagesAdded },
                existingPairKeys: state.existingPairKeys
            )
            return try preparePagesWithoutInserting(
                from: parsed.imageURLs,
                input: input
            )
        }
    }

    func stepOnce(maxPages: Int?,
                  selectors: Selectors,
                  env: FetchEnv,
                  state: inout FetchState) async throws -> StepOutcome {
        if shouldStop(maxPages: maxPages, pagesAdded: state.pagesAdded) { return .finished }
        guard state.visitedURLs.insert(state.currentURL.absoluteString).inserted else { return .finished }

        let parsed = try await fetchAndParse(
            url: state.currentURL,
            referer: state.previousURL,
            selectorTitle: selectors.title,
            selectorImage: selectors.image,
            http: http
        )
        guard !parsed.imageURLs.isEmpty else { return .finished }

        await maybeSetCover(from: parsed,
                            referer: state.currentURL,
                            env: env,
                            state: &state)

        let prep = try await prepareBatch(from: parsed,
                                          at: state.currentURL,
                                          maxPages: maxPages,
                                          state: state)
        state.existingPairKeys = prep.updatedKeys
        state.pendingPages.append(contentsOf: prep.prepared)

        state.pagesAdded += prep.result.inserted
        state.currentMaxIndex = prep.result.newStartingIndex

        state.preparedSinceLastCommit += prep.prepared.count
        try await finalizeIfNeeded(state: &state,
                                   env: env,
                                   force: prep.result.didReachMax)
        if prep.result.didReachMax { return .finished }

        if shouldStop(maxPages: maxPages, pagesAdded: state.pagesAdded) {
            try await finalizeIfNeeded(state: &state, env: env, force: true)
            return .finished
        }

        guard let next = advance(from: state.currentURL, using: parsed.doc, selectorNext: selectors.next, visited: state.visitedURLs) else {
            try await finalizeIfNeeded(state: &state, env: env, force: true)
            return .finished
        }

        let previous = state.currentURL
        return .advance(to: next, previous: previous)
    }
}
