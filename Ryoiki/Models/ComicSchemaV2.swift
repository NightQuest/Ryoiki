//
//  ComicSchemaV2.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-26.
//

import Foundation
import SwiftData

enum ComicSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Comic.self, ComicPage.self]
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

        var coverImage: Data?

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

        @Relationship(deleteRule: .cascade)
        var images: [ComicPageImages] = []

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
    class ComicPageImages {
        @Attribute(.unique)
        var id = UUID()

        @Relationship(inverse: \ComicPage.images)
        var comicPage: ComicPage

        var index: Int = 0

        var imageURL: String
        var downloadPath: String = ""

        init(comicPage: ComicPage,
             index: Int,
             imageURL: String) {
            self.comicPage = comicPage
            self.index = index
            self.imageURL = imageURL
        }
    }
}
