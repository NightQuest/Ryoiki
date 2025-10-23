import Foundation
import SwiftSoup

// Namespace for ComicDownloader helper types to avoid ambiguity
enum CDTypes {
    struct PageSpec: Sendable {
        let index: Int
        let title: String
        let pageURL: String
        let imageURL: String
    }

    struct InsertionResult: Sendable {
        let inserted: Int
        let didReachMax: Bool
        let newStartingIndex: Int
    }

    struct PreparationResult: Sendable {
        let prepared: [PageSpec]
        let result: InsertionResult
        let updatedKeys: Set<String>
    }

    struct ParseResult: Sendable {
        let doc: Document
        let title: String?
        let imageURLs: [URL]
    }

    struct PreparationInput: Sendable {
        let currentPageURL: URL
        let startingIndex: Int
        let titleText: String?
        let maxPages: Int?
        let existingPairKeys: Set<String>
    }
}
