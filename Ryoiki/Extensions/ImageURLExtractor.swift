import Foundation
import SwiftSoup

/// Resolve a possibly relative URL string against an optional base, after trimming whitespace/newlines.
/// If `base` is nil, returns `URL(string:)` which may be relative; callers may prefer absolute URLs.
@inline(__always)
func resolveURL(_ string: String, base: URL?) -> URL? {
    _absoluteURL(string, base: base)
}

private let _imageURLAttributeNames: [String] = [
    "data-orig-file", "data-image",

    "data-lazy-src", "data-original", "data-zoom-image",
    "data-large_image", "data-hires", "data-src",

    "data-url",
    "src"
]

private func _absoluteURL(_ string: String, base: URL?) -> URL? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if let base = base {
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }
    // No explicit base; return absolute URL if possible
    return URL(string: trimmed)
}

private func _normalizeImageURLString(_ urlString: String) -> String {
    guard let url = URL(string: urlString),
          var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return urlString
    }

    // Known variant params commonly used by WordPress/CDNs
    let dropParams: Set<String> = [
        "resize", "w", "h", "width", "height", "fit", "crop", "quality", "q"
    ]

    if let items = comps.queryItems, !items.isEmpty {
        let kept = items.filter { item in
            guard let name = item.name.lowercased().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return false }
            return !dropParams.contains(item.name.lowercased()) && !dropParams.contains(name)
        }
        comps.queryItems = kept.isEmpty ? nil : kept
    }

    // Build a host-agnostic dedupe key using last directory + filename when possible
    // Example: https://i0.wp.com/site.com/wp-content/uploads/2025/08/chap4pg76.png?fit=... -> "uploads/chap4pg76.png"
    if let path = comps.percentEncodedPath.removingPercentEncoding, !path.isEmpty {
        // Split path into components and take the last directory and the last component (filename)
        let parts = path.split(separator: "/").map(String.init)
        if let filename = parts.last {
            let lastDir = parts.dropLast().last ?? ""
            let key = lastDir.isEmpty ? filename : lastDir + "/" + filename
            return key
        }
    }

    // Fallback to the sanitized URL string if path-based key cannot be formed
    return comps.string ?? urlString
}

private func _parseSrcset(_ srcset: String) -> [(width: Int, url: String)] {
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

private func _firstNonEmptyAttribute(in element: Element, names: [String]) -> String? {
    for name in names {
        if let value = try? element.attr(name), !value.isEmpty {
            return value
        }
    }
    return nil
}

private func _bestURLFromSrcAndSrcset(_ element: Element) -> String? {
    func attr(_ element: Element, _ name: String) -> String? {
        (try? element.attr(name)).flatMap { $0.isEmpty ? nil : $0 }
    }

    // Read attributes
    let src: String? = attr(element, "src")
    let srcsetValue: String = attr(element, "srcset") ?? attr(element, "data-srcset") ?? ""

    // Parse srcset and pick the largest width candidate if available
    let candidates = _parseSrcset(srcsetValue).sorted { lhs, rhs in lhs.width > rhs.width }
    if let largest = candidates.first, !largest.url.isEmpty {
        return largest.url
    }

    // Fallback to src if no srcset candidates
    return src
}

private func _preferredURLString(for element: Element) -> String? {
    // Scan all known attributes in declared order, excluding those handled by src/srcset logic.
    let specials: Set<String> = ["src", "srcset", "data-srcset"]
    let candidateNames = _imageURLAttributeNames.filter { !specials.contains($0) }
    if let v = _firstNonEmptyAttribute(in: element, names: candidateNames) {
        return v
    }

    // Fallback to src/srcset logic
    return _bestURLFromSrcAndSrcset(element)
}

private func _absURLFromElementAttributes(_ element: Element) -> URL? {
    for name in _imageURLAttributeNames {
        if let abs = (try? element.absUrl(name)), !abs.isEmpty, let absURL = URL(string: abs) {
            return absURL
        }
    }
    return nil
}

private func _resolveURLString(_ candidate: String, for element: Element, baseURL: URL?) -> URL? {
    // Try resolving with explicit base first
    if let resolved = _absoluteURL(candidate, base: baseURL) {
        if baseURL == nil, resolved.scheme == nil {
            return _absURLFromElementAttributes(element)
        } else {
            return resolved
        }
    }

    // URL(string:) failed; try absUrl fallbacks
    return _absURLFromElementAttributes(element)
}

extension Document {
    /// Extract image URLs using WordPress-specific attribute preferences and srcset logic.
    /// - Parameters:
    ///   - selector: CSS selector for elements containing image URLs (e.g., "img").
    ///   - baseURL: Optional base URL to resolve relative URLs.
    /// - Returns: Array of resolved URLs.
    func imageURLs(selector: String, baseURL: URL? = nil) -> [URL] {
        do {
            let elements = try self.select(selector).array()

            // Build (element, urlString) pairs while preserving mapping
            let pairs: [(Element, String)] = elements.compactMap { element in
                guard let candidate = _preferredURLString(for: element), !candidate.isEmpty else { return nil }
                return (element, candidate)
            }

            // De-duplicate by normalized URL string while preserving first occurrence and its element
            var seen = Set<String>()
            var uniquePairs: [(Element, String)] = []
            uniquePairs.reserveCapacity(pairs.count)
            for (el, u) in pairs where !u.isEmpty {
                let key = _normalizeImageURLString(u)
                if seen.insert(key).inserted {
                    uniquePairs.append((el, u))
                }
            }

            // Resolve URLs to absolute URLs when possible
            var result: [URL] = []
            result.reserveCapacity(uniquePairs.count)

            for (element, candidate) in uniquePairs {
                if let resolved = _resolveURLString(candidate, for: element, baseURL: baseURL) {
                    result.append(resolved)
                }
            }

            return result
        } catch {
            return []
        }
    }
}
