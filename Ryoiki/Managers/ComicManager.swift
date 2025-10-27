//
//  ComicManager.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-21.
//

import Foundation
import SwiftData

// MARK: - ComicManager

/// A façade responsible for fetching comic pages (sequentially), parsing HTML, and downloading images.
///
/// - Concurrency:
///   - Network and parsing work off the main actor.
///   - All model mutations (SwiftData) hop to the main actor.
///   - File IO is performed off the main actor; model updates after IO hop back to main.
/// - Platform:
///   - Platform agnostic; uses Foundation and Swift concurrency only.
struct ComicManager: Sendable {
    let http: HTTPClientProtocol

    // MARK: Errors
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
}
