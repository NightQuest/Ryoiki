import Foundation
import SwiftSoup

struct ImageURLExtractor {
    // Resolve absolute URLs relative to a base URL
    private func absoluteURL(_ string: String, base: URL) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    // Parse srcset into (width, url) pairs
    private func parseSrcset(_ srcset: String) -> [(width: Int, url: String)] {
        srcset
            .split(separator: ",")
            .compactMap { item -> (Int, String)? in
                let parts = item.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard let first = parts.first else { return nil }
                let url = String(first)
                if let last = parts.last, last.hasSuffix("w"), let width = Int(last.dropLast()) {
                    return (width, url)
                }
                return (0, url)
            }
    }

    // Public API to extract image URLs from a document
    func extractImageURLs(in doc: Document, selector: String, baseURL: URL) -> [URL] {
        do {
            let elements = try doc.select(selector).array()
            return elements.compactMap { element -> URL? in
                let urlString: String? = {
                    if let srcset = try? element.attr("srcset"), !srcset.isEmpty {
                        let candidates = parseSrcset(srcset)
                        if let largest = candidates.max(by: { $0.width < $1.width }) {
                            return largest.url
                        }
                    }
                    if let src = (try? element.attr("src")), !src.isEmpty { return src }
                    if let dataSrc = (try? element.attr("data-src")), !dataSrc.isEmpty { return dataSrc }
                    return nil
                }()
                return urlString.flatMap { absoluteURL($0, base: baseURL) }
            }
        } catch {
            return []
        }
    }
}
