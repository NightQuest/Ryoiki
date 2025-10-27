//
//  ComicManager+Navigation.swift
//  Ryoiki
//

import Foundation
import SwiftSoup

// MARK: - Navigation & Retry
extension ComicManager {
    func nextLink(in doc: Document, selector: String, baseURL: URL) -> URL? {
        guard !selector.isEmpty else { return nil }
        if let href = try? doc.select(selector).first()?.attr("href") {
            return resolveURL(href, base: baseURL)
        }
        return nil
    }

    func fetchHTMLWithRetry(from url: URL, referer: URL?, attempts: Int = 3) async throws -> String {
        var lastError: Swift.Error?
        for attempt in 0..<max(1, attempts) {
            do {
                return try await self.html(from: url, referer: referer)
            } catch {
                // Do not retry on cancellation
                if error is CancellationError { throw error }
                if let scraperError = error as? ComicManager.Error, case .cancelled = scraperError { throw scraperError }
                lastError = error
                if attempt < attempts - 1 { try? await Task.sleep(for: .milliseconds(200 * (attempt + 1))) }
            }
        }
        throw lastError ?? ComicManager.Error.network(NSError(domain: "Unknown", code: -1))
    }

    func advance(from current: URL, using doc: Document, selectorNext: String, visited: Set<String>) -> URL? {
        guard let next = nextLink(in: doc, selector: selectorNext, baseURL: current) else { return nil }
        guard !visited.contains(next.absoluteString) else { return nil }
        return next
    }
}
