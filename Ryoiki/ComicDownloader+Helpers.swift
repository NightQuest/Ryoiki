import Foundation
import SwiftSoup

private let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
"(KHTML, like Gecko) Version/15.1 Safari/605.1.15"

// MARK: - Fetch & Parse

func fetchAndParse(url: URL, referer: URL?, selectorTitle: String, selectorImage: String) async throws -> CDTypes.ParseResult {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
    if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
        throw URLError(.badServerResponse)
    }

    guard let htmlString = String(data: data, encoding: .utf8) else {
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    let doc = try SwiftSoup.parse(htmlString, url.absoluteString)
    let title = parseTitle(in: doc, selector: selectorTitle)
    let imageURLs = doc.imageURLs(selector: selectorImage, baseURL: url)

    return CDTypes.ParseResult(doc: doc, title: title, imageURLs: imageURLs)
}

// MARK: - Preparation (no inserts, main-actor for model-safety by caller convention)

@MainActor
func preparePagesWithoutInserting(from imageURLs: [URL], input: CDTypes.PreparationInput) throws -> CDTypes.PreparationResult {
    var prepared: [CDTypes.PageSpec] = []
    var keys = input.existingPairKeys
    var inserted = 0
    var nextIndex = input.startingIndex

    for imageURL in imageURLs {
        let key = "\(input.currentPageURL.absoluteString)|\(imageURL.absoluteString)"
        if keys.contains(key) { continue }

        nextIndex += 1
        let spec = CDTypes.PageSpec(
            index: nextIndex,
            title: input.titleText ?? "",
            pageURL: input.currentPageURL.absoluteString,
            imageURL: imageURL.absoluteString
        )
        prepared.append(spec)
        keys.insert(key)
        inserted += 1

        if let maxPages = input.maxPages, inserted >= maxPages {
            let result = CDTypes.InsertionResult(inserted: inserted, didReachMax: true, newStartingIndex: nextIndex)
            return CDTypes.PreparationResult(prepared: prepared, result: result, updatedKeys: keys)
        }
    }

    let result = CDTypes.InsertionResult(inserted: inserted, didReachMax: false, newStartingIndex: nextIndex)
    return CDTypes.PreparationResult(prepared: prepared, result: result, updatedKeys: keys)
}

// MARK: - Local helpers

private func parseTitle(in doc: Document, selector: String) -> String? {
    guard !selector.isEmpty,
          let raw = try? doc.select(selector).first()?.text()
    else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private extension Document {
    func imageURLs(selector: String, baseURL: URL) -> [URL] {
        guard !selector.isEmpty else { return [] }
        do {
            let elements = try select(selector).array()
            var seen = Set<String>()
            return elements.compactMap { el -> URL? in
                let src = (try? el.attr("src")) ?? ""
                let dataSrc = (try? el.attr("data-src")) ?? ""
                let candidate = !src.isEmpty ? src : (!dataSrc.isEmpty ? dataSrc : "")
                guard !candidate.isEmpty, seen.insert(candidate).inserted else { return nil }
                return URL(string: candidate, relativeTo: baseURL)?.absoluteURL
            }
        } catch {
            return []
        }
    }
}
