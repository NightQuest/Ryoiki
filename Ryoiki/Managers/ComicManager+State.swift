//
//  ComicManager+State.swift
//  Ryoiki
//

import Foundation
import SwiftData
import SwiftSoup

// MARK: - Fetch Types & State
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

    struct Selectors { let title: String; let image: String; let next: String }
    struct FetchEnv { let comic: Comic; let context: ModelContext }

    enum StepOutcome { case advance(to: URL, previous: URL?); case finished }

    @inline(__always)
    func shouldStop(maxPages: Int?, pagesAdded: Int) -> Bool {
        if let max = maxPages, pagesAdded >= max { return true }
        return false
    }

    func applyPendingPages(state: inout FetchState, env: FetchEnv) throws {
        guard !state.pendingPages.isEmpty else { return }

        // Determine the starting sequential page number (continue from current max in DB)
        var nextPageNumber = (env.comic.pages.max(by: { $0.index < $1.index })?.index ?? 0) + 1

        // Assign a normalized, sequential page number per unique pageURL within the pending batch
        var pageNumberByURL: [String: Int] = [:]
        for spec in state.pendingPages where pageNumberByURL[spec.pageURL] == nil {
            pageNumberByURL[spec.pageURL] = nextPageNumber
            nextPageNumber += 1
        }

        // Insert pages using the normalized page index so DB matches on-disk naming
        for spec in state.pendingPages {
            let normalizedIndex = pageNumberByURL[spec.pageURL] ?? spec.index
            let page = ComicPage(
                comic: env.comic,
                index: normalizedIndex,
                title: spec.title,
                pageURL: spec.pageURL
            )
            let image = ComicImage(comicPage: page, index: 0, imageURL: spec.imageURL)
            page.images.append(image)
            env.context.insert(page)
        }
        try env.context.save()
        state.pendingPages.removeAll(keepingCapacity: true)
    }

    func finalizeIfNeeded(state: inout FetchState, env: FetchEnv, force: Bool = false) async throws {
        if force || state.preparedSinceLastCommit >= state.commitThreshold {
            try applyPendingPages(state: &state, env: env)
            state.preparedSinceLastCommit = 0
            await Task.yield()
        }
    }

    func maybeSetCover(from parsed: CMTypes.ParseResult, referer: URL, env: FetchEnv, state: inout FetchState) async {
        guard state.initiallyEmpty, !state.didSetCoverAtFetchTime, let firstImageURL = parsed.imageURLs.first else { return }
        do {
            let data = try await getData(firstImageURL, referer: referer)
            if env.comic.coverImage == nil {
                env.comic.coverImage = data
                try? env.context.save()
            }
            state.didSetCoverAtFetchTime = true
        } catch { }
    }

    func prepareBatch(from parsed: CMTypes.ParseResult, at url: URL, maxPages: Int?, state: FetchState) async throws -> CMTypes.PreparationResult {
        let input = CMTypes.PreparationInput(
            currentPageURL: url,
            startingIndex: state.currentMaxIndex,
            titleText: parsed.title,
            maxPages: maxPages.map { $0 - state.pagesAdded },
            existingPairKeys: state.existingPairKeys
        )
        return try preparePagesWithoutInserting(from: parsed.imageURLs, input: input)
    }

    func stepOnce(maxPages: Int?, selectors: Selectors, env: FetchEnv, state: inout FetchState) async throws -> StepOutcome {
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

        await maybeSetCover(from: parsed, referer: state.currentURL, env: env, state: &state)

        let prep = try await prepareBatch(from: parsed, at: state.currentURL, maxPages: maxPages, state: state)
        state.existingPairKeys = prep.updatedKeys
        state.pendingPages.append(contentsOf: prep.prepared)

        state.pagesAdded += prep.result.inserted
        state.currentMaxIndex = prep.result.newStartingIndex

        state.preparedSinceLastCommit += prep.prepared.count
        try await finalizeIfNeeded(state: &state, env: env, force: prep.result.didReachMax)
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

// MARK: - Error Mapping
extension ComicManager {
    @inline(__always)
    func map(_ error: HTTPClientError) -> Swift.Error {
        switch error {
        case .badStatus(let code): return Error.badStatus(code)
        case .cancelled: return CancellationError()
        case .network(let underlying): return Error.network(underlying)
        }
    }
}
