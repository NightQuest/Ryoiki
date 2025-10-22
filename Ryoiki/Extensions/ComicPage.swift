//
//  ComicPage.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-21.
//
import Foundation

extension ComicPage {
    /// Returns the file URL for the downloaded image if available.
    /// - Note: This handles both stored absolute file URL strings (e.g., "file:///...")
    ///   and plain file system paths.
    var downloadedFileURL: URL? {
        guard !downloadPath.isEmpty else { return nil }
        if let url = URL(string: downloadPath), url.scheme != nil { // e.g., file:///...
            return url
        } else {
            return URL(fileURLWithPath: downloadPath)
        }
    }
}
