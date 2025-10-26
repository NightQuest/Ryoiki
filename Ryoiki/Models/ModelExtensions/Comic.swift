//
//  Comic.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-25.
//

import Foundation

extension Comic {
    /// Sets the cover image from a file URL by loading its data.
    /// If loading fails, the cover image is not modified.
    func setCoverImage(from fileURL: URL) {
        if let data = try? Data(contentsOf: fileURL) {
            self.coverImage = data
        }
    }

    var dedupedPageCount: Int {
        let uniqueByURL = Set(self.pages.map { $0.pageURL })
        return uniqueByURL.count
    }
}
