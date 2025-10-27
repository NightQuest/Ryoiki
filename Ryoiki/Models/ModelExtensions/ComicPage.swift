//
//  ComicPage.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-21.
//
import Foundation

extension ComicPage {
    /// Returns the file URL for the first downloaded image if available.
    /// - Note: This handles both stored absolute file URL strings (e.g., "file:///...")
    ///   and plain file system paths.
    var firstDownloadedFileURL: URL? {
        guard let path = images.min(by: { $0.index < $1.index })?.downloadPath, !path.isEmpty else { return nil }
        if let url = URL(string: path), url.scheme != nil { // e.g., file:///...
            return url
        } else {
            return URL(fileURLWithPath: path)
        }
    }

    /// Returns the first image's URL as a String
    var firstImageURLString: String? { images.min(by: { $0.index < $1.index })?.imageURL }

    /// Returns file URLs for all downloaded images on this page, ordered by image index.
    var downloadedFileURLs: [URL] {
        images
            .sorted(by: { $0.index < $1.index })
            .compactMap { img in
                let path = img.downloadPath
                guard !path.isEmpty else { return nil }
                if let url = URL(string: path), url.scheme != nil {
                    return url
                } else {
                    return URL(fileURLWithPath: path)
                }
            }
    }
}

extension ComicImage {
    /// Returns a resolved file URL for this image's downloaded path, if present and valid.
    /// Handles both absolute file URLs (e.g., file://...) and plain filesystem paths.
    var fileURL: URL? {
        guard !downloadPath.isEmpty else { return nil }
        if let u = URL(string: downloadPath), u.scheme != nil {
            return u
        } else {
            return URL(fileURLWithPath: downloadPath)
        }
    }
}
