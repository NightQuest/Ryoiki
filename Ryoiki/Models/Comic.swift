import Foundation
import SwiftData

@Model
final class Comic {
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
