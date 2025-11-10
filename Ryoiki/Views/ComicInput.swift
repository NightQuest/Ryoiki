import Foundation

/// Simple DTO that is handed back to the caller when the user taps Add/Save in the editor.
public struct ComicInput {
    public let name: String
    public let author: String
    public let description: String
    public let url: String
    public let firstPageURL: String
    public let selectorImage: String
    public let selectorTitle: String
    public let selectorNext: String

    public init(name: String,
                author: String,
                description: String,
                url: String,
                firstPageURL: String,
                selectorImage: String,
                selectorTitle: String,
                selectorNext: String) {
        self.name = name
        self.author = author
        self.description = description
        self.url = url
        self.firstPageURL = firstPageURL
        self.selectorImage = selectorImage
        self.selectorTitle = selectorTitle
        self.selectorNext = selectorNext
    }
}
