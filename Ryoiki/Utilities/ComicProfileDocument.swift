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

private enum ComicProfileJSON {
    static func normalized(from raw: Data) throws -> Data {
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
        return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
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
        self.data = try ComicProfileJSON.normalized(from: raw)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: data)
    }
}

extension ComicProfileDocument {
    static func load(from url: URL) throws -> ComicProfileDocument {
        // Gain access to security-scoped resource on iOS
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        // Coordinate reading (important for iCloud and external providers)
        var readError: NSError?
        var wrapper: FileWrapper?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &readError) { readableURL in
            wrapper = try? FileWrapper(url: readableURL, options: .immediate)
        }

        if let readError { throw readError }
        guard let wrapper else { throw CocoaError(.fileReadUnknown) }

        // Extract data and validate/normalize
        let raw = wrapper.regularFileContents ?? Data()
        let normalized = try ComicProfileJSON.normalized(from: raw)
        return ComicProfileDocument(data: normalized)
    }
}
