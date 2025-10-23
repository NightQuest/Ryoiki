import Foundation
import SwiftData

typealias Comic = ComicSchemaV1.Comic
typealias ComicPage = ComicSchemaV1.ComicPage

enum ComicSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

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
        var imageURL: String

        var downloadPath: String = ""

        init(comic: Comic,
             index: Int,
             title: String,
             pageURL: String,
             imageURL: String) {
            self.comic = comic
            self.index = index
            self.title = title
            self.pageURL = pageURL
            self.imageURL = imageURL
        }
    }
}
