import Foundation
import UniformTypeIdentifiers

/// Sanitizes a filename by removing illegal characters and trimming whitespace/newlines.
func sanitizeFilename(_ filename: String) -> String {
    let illegalFileNameCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
    let components = filename.components(separatedBy: illegalFileNameCharacters)
    let sanitized = components.joined()
    return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Determines a preferred file extension from a Content-Type header or a URL path extension, with a fallback.
func fileExtension(contentType: String?, urlExtension: String?, fallback: String) -> String {
    if let contentType, let type = UTType(mimeType: contentType), let ext = type.preferredFilenameExtension {
        return ext
    }
    if let urlExtension, !urlExtension.isEmpty { return urlExtension }
    return fallback
}

/// Decodes a data URL of the form `data:[<mediatype>][;base64],<data>` into its media type and data.
func decodeDataURL(_ urlString: String) -> (mediatype: String, data: Data)? {
    guard urlString.hasPrefix("data:") else { return nil }
    guard let commaIndex = urlString.firstIndex(of: ",") else { return nil }

    let meta = String(urlString[urlString.index(urlString.startIndex, offsetBy: 5)..<commaIndex]) // skip "data:"
    let dataPart = String(urlString[urlString.index(after: commaIndex)...])

    let isBase64 = meta.contains(";base64")
    let mediatype = meta.components(separatedBy: ";").first ?? "application/octet-stream"

    if isBase64 {
        guard let data = Data(base64Encoded: dataPart) else { return nil }
        return (mediatype, data)
    } else {
        guard let decoded = dataPart.removingPercentEncoding,
              let data = decoded.data(using: .utf8) else { return nil }
        return (mediatype, data)
    }
}
