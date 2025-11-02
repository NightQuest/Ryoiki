//
//  ComicSchemaV5.swift
//  Ryoiki
//
//  Created by Stardust on 2025-11-01.
//

import Foundation
import SwiftData

enum ComicSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Comic.self, ComicPage.self, ComicPageImage.self]
    }

    @Model
    class Comic {
        @Attribute(.unique)
        var id = UUID()

        var name: String
        var author: String
        var descriptionText: String

        var url: String
        var firstPageURL: String

        var selectorImage: String
        var selectorTitle: String
        var selectorNext: String

        @Attribute(.externalStorage)
        var coverImage: Data?

        // Cached, UI-facing counts and paths to avoid heavy relationship traversal in views
        var pageCount: Int = 0
        var imageCount: Int = 0
        var downloadedImageCount: Int = 0
        var coverFilePath: String = ""

        @Relationship(deleteRule: .cascade)
        var pages: [ComicPage] = []

        init(name: String,
             author: String,
             descriptionText: String,
             url: String,
             firstPageURL: String,
             selectorImage: String,
             selectorTitle: String,
             selectorNext: String) {
            self.name = name
            self.author = author
            self.descriptionText = descriptionText
            self.url = url
            self.firstPageURL = firstPageURL
            self.selectorImage = selectorImage
            self.selectorTitle = selectorTitle
            self.selectorNext = selectorNext
        }
    }

    @Model
    class ComicPage {
        @Attribute(.unique)
        var id = UUID()

        @Relationship(inverse: \Comic.pages)
        var comic: Comic

        var index: Int = 0
        var title: String = ""

        var pageURL: String

        var dateFetched: Date = Date.now

        @Relationship(deleteRule: .cascade)
        var images: [ComicPageImage] = []

        init(comic: Comic,
             index: Int,
             title: String,
             pageURL: String) {
            self.comic = comic
            self.index = index
            self.title = title
            self.pageURL = pageURL
        }
    }

    @Model
    class ComicPageImage {
        @Attribute(.unique)
        var id = UUID()

        @Relationship(inverse: \ComicPage.images)
        var comicPage: ComicPage

        var index: Int = 0

        // Denormalized copy of parent page's URL for fast duplicate detection
        var pageURL: String = ""

        var imageURL: String
        var fileURL: URL?

        // Cached flag to avoid frequent disk checks in UI
        var isDownloaded: Bool = false

        var dateDownloaded: Date?

        init(comicPage: ComicPage,
             index: Int,
             imageURL: String) {
            self.comicPage = comicPage
            self.index = index
            self.imageURL = imageURL
        }
    }
}
