//
//  ComicPage.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-21.
//
import Foundation

extension ComicPage {

    /// Returns file URLs for all downloaded images on this page, ordered by image index.
    var downloadedFileURLs: [URL] {
        images
            .sorted(by: { $0.index < $1.index })
            .compactMap { img in
                let url = img.fileURL
                guard url?.scheme != nil else { return nil }

                return url!
            }
    }
}
