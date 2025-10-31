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
        // The passed-in `comic` is expected to belong to the provided `context` (a background context in callers)
        // Snapshot primitive values directly from this context-bound model
        let comicID = comic.id
        let selectorNext = comic.selectorNext
        let selectorImage = comic.selectorImage
        let selectorTitle = comic.selectorTitle
        let firstPageURLString = comic.firstPageURL

        if selectorImage.isEmpty { throw Error.missingSelector("selectorImage") }

        // Resolve the starting URL and previous URL using background fetches of pages
        // Find the last page (highest index) if any, and its predecessor as referer
        let lastPage: ComicPage? = try context.fetch(
            FetchDescriptor<ComicPage>(
                predicate: #Predicate { $0.comic.id == comicID },
                sortBy: [SortDescriptor(\.index, order: .forward)]
            )
        ).last

        let lastIndex: Int = lastPage?.index ?? Int.min

        let previousPage: ComicPage? = {
            guard lastIndex != Int.min else { return nil }
            return try? context.fetch(
                FetchDescriptor<ComicPage>(
                    predicate: #Predicate { $0.comic.id == comicID && $0.index < lastIndex },
                    sortBy: [SortDescriptor(\.index, order: .reverse)]
                )
            ).first
        }()

        // Compute current URL (continue from last page if exists; otherwise from configured firstPageURL)
        let currentURL: URL = {
            if let last = lastPage, let u = URL(string: last.pageURL) { return u }
            guard let u = URL(string: firstPageURLString.trimmedNilIfEmpty ?? "") else { return URL(string: "about:blank")! }
            return u
        }()

        // Compute referer (previous page URL if available, else fallback to firstPageURL)
        let previousURL: URL? = {
            if let prev = previousPage, let u = URL(string: prev.pageURL) { return u }
            return URL(string: firstPageURLString.trimmedNilIfEmpty ?? "")
        }()

        // Find current maximum index in existing pages (background fetch)
        let currentMaxIndex: Int = lastPage?.index ?? 0

        // Build duplicate detection set from a rolling window of recent pages to reduce upfront cost
        let windowStartIndex = max(0, currentMaxIndex - 200)
        let recentImages: [ComicImage] = try context.fetch(
            FetchDescriptor<ComicImage>(
                predicate: #Predicate { $0.comicPage.comic.id == comicID && $0.comicPage.index >= windowStartIndex }
            )
        )
        let existingPairKeys: Set<String> = Set(recentImages.map { img in
            let pageURL = img.pageURL.isEmpty ? img.comicPage.pageURL : img.pageURL
            return "\(pageURL)|\(img.imageURL)"
        })

        let initiallyEmpty: Bool = (lastPage == nil)

        let selectors = Selectors(title: selectorTitle, image: selectorImage, next: selectorNext)

        var state = FetchState(
            didSetCoverAtFetchTime: false,
            existingPairKeys: existingPairKeys,
            currentMaxIndex: currentMaxIndex,
            visitedURLs: [],
            pagesAdded: 0,
            currentURL: currentURL,
            previousURL: previousURL,
            pendingPages: [],
            preparedSinceLastCommit: 0,
            commitThreshold: 100,
            initiallyEmpty: initiallyEmpty
        )

        try Task.checkCancellation()

        let env = FetchEnv(comic: comic, context: context)

        // Ensure we always try to commit pending pages on function exit/cancellation
        defer {
            do { try self.applyPendingPages(state: &state, env: env) } catch { }
        }

        // Sequential loop
        while true {
            try Task.checkCancellation()

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
