import Foundation
import UniformTypeIdentifiers
import SwiftUI

private enum ComicProfileValidationError: LocalizedError {
    case invalidFormat
    case missingKey(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "File is not valid JSON or not a JSON object."
        case .missingKey(let key):
            return "Missing required key: \(key)."
        }
    }
}

struct ComicProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        let raw = configuration.file.regularFileContents ?? Data()
        // Validate structure without touching actor-isolated Codable types
        let object = try JSONSerialization.jsonObject(with: raw, options: [])
        guard let dict = object as? [String: Any] else {
            throw ComicProfileValidationError.invalidFormat
        }
        let requiredKeys = [
            "version",
            "name",
            "author",
            "descriptionText",
            "url",
            "firstPageURL",
            "selectorImage",
            "selectorTitle",
            "selectorNext"
        ]
        for key in requiredKeys where dict[key] == nil { throw ComicProfileValidationError.missingKey(key) }
        // Normalize with pretty printing
        let normalized = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        self.data = normalized
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: data)
    }
}
