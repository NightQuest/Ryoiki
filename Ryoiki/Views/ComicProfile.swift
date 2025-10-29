import Foundation

struct ComicProfile: Codable {
    var version: Int = 1

    var name: String
    var author: String
    var descriptionText: String

    var url: String
    var firstPageURL: String

    var selectorImage: String
    var selectorTitle: String
    var selectorNext: String

    init(name: String,
         author: String,
         descriptionText: String,
         url: String,
         firstPageURL: String,
         selectorImage: String,
         selectorTitle: String,
         selectorNext: String,
         version: Int = 1) {
        self.version = version
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

extension ComicProfile {
    init(from comic: Comic) {
        self.init(
            name: comic.name,
            author: comic.author,
            descriptionText: comic.descriptionText,
            url: comic.url,
            firstPageURL: comic.firstPageURL,
            selectorImage: comic.selectorImage,
            selectorTitle: comic.selectorTitle,
            selectorNext: comic.selectorNext,
            version: 1
        )
    }

    func buildComic() -> Comic {
        // Build and return a Comic instance.
        // This does not perform insertion or saving.
        Comic(
            name: name,
            author: author,
            descriptionText: descriptionText,
            url: url,
            firstPageURL: firstPageURL,
            selectorImage: selectorImage,
            selectorTitle: selectorTitle,
            selectorNext: selectorNext
        )
    }
}
