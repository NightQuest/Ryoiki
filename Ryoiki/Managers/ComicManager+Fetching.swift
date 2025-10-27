//
//  ComicManager+Fetching.swift
//  Ryoiki
//

import Foundation
import SwiftData

// MARK: - Page Fetching (sequential)
extension ComicManager {
    /// Fetches pages sequentially for a comic. Maintains previous functionality.
    /// - Returns: Count of pages added.
    func fetchPages(
        for comic: Comic,
        context: ModelContext,
        maxPages: Int? = nil
    ) async throws -> Int {
        // Snapshot model-derived values that require main-actor access once up front
        let firstPageURL: URL = try await MainActor.run { () -> URL in
            let firstPage = comic.pages.last?.pageURL ?? comic.firstPageURL
            let firstPageString = firstPage
            guard let firstPageTrimmed = firstPageString.trimmedNilIfEmpty,
                  let url = URL(string: firstPageTrimmed) else {
                throw Error.invalidBaseURL
            }
            return url
        }
        let prevPageURL: URL = try await MainActor.run { () -> URL in
            let firstPage = comic.pages.last(where: { page in
                page.pageURL != firstPageURL.absoluteString
            })?.pageURL ?? comic.firstPageURL
            let firstPageString = firstPage
            guard let firstPageTrimmed = firstPageString.trimmedNilIfEmpty,
                  let url = URL(string: firstPageTrimmed) else {
                throw Error.invalidBaseURL
            }
            return url
        }

        let selectorNext = comic.selectorNext
        let selectorImage = comic.selectorImage
        let selectorTitle = comic.selectorTitle

        if selectorImage.isEmpty { throw Error.missingSelector("selectorImage") }

        // Build a fast lookup of existing (pageURL|imageURL) pairs to avoid O(n) scans on main actor
        let existingPairKeys: Set<String> = await MainActor.run {
            Set(comic.pages.flatMap { page in
                page.images.map { "\(page.pageURL)|\($0.imageURL)" }
            })
        }

        // Find current maximum index in existing pages (main-actor snapshot once)
        let currentMaxIndex: Int = await MainActor.run {
            comic.pages.max(by: { $0.index < $1.index })?.index ?? -1
        }

        let initiallyEmpty: Bool = await MainActor.run { comic.pages.isEmpty }

        let selectors = Selectors(title: selectorTitle, image: selectorImage, next: selectorNext)

        var state = FetchState(
            didSetCoverAtFetchTime: false,
            existingPairKeys: existingPairKeys,
            currentMaxIndex: currentMaxIndex,
            visitedURLs: [],
            pagesAdded: 0,
            currentURL: firstPageURL,
            previousURL: prevPageURL,
            pendingPages: [],
            preparedSinceLastCommit: 0,
            commitThreshold: 5,
            initiallyEmpty: initiallyEmpty
        )

        let env = FetchEnv(comic: comic, context: context)

        // Ensure we always try to commit pending pages on function exit/cancellation
        defer {
            Task { @MainActor in
                do { try self.applyPendingPages(state: &state, env: env) } catch { }
            }
        }

        // Sequential loop
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
                try await finalizeIfNeeded(state: &state, env: env, force: true)
                return state.pagesAdded
            }
        }
    }
}
