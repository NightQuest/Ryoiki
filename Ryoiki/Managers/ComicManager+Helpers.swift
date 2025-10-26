import Foundation
import SwiftSoup

// MARK: - Fetch & Parse

func fetchAndParse(url: URL,
                   referer: URL?,
                   selectorTitle: String,
                   selectorImage: String,
                   http: HTTPClientProtocol) async throws -> CMTypes.ParseResult {
    let (data, response) = try await http.get(url, referer: referer)
    guard (200..<300).contains(response.statusCode) else {
        throw ComicManager.Error.badStatus(response.statusCode)
    }
    guard let htmlString = String(data: data, encoding: .utf8) else {
        throw ComicManager.Error.parse
    }

    let doc = try SwiftSoup.parse(htmlString, url.absoluteString)
    let title = parseTitle(in: doc, selector: selectorTitle)
    let imageURLs = doc.imageURLs(selector: selectorImage, baseURL: url)

    return CMTypes.ParseResult(doc: doc, title: title, imageURLs: imageURLs)
}

// MARK: - Preparation (no inserts, main-actor for model-safety by caller convention)

@MainActor
func preparePagesWithoutInserting(from imageURLs: [URL], input: CMTypes.PreparationInput) throws -> CMTypes.PreparationResult {
    var prepared: [CMTypes.PageSpec] = []
    var keys = input.existingPairKeys
    var inserted = 0
    var nextIndex = input.startingIndex

    for imageURL in imageURLs {
        let key = "\(input.currentPageURL.absoluteString)|\(imageURL.absoluteString)"
        if keys.contains(key) { continue }

        nextIndex += 1
        let spec = CMTypes.PageSpec(
            index: nextIndex,
            title: input.titleText ?? "",
            pageURL: input.currentPageURL.absoluteString,
            imageURL: imageURL.absoluteString
        )
        prepared.append(spec)
        keys.insert(key)
        inserted += 1

        if let maxPages = input.maxPages, inserted >= maxPages {
            let result = CMTypes.InsertionResult(inserted: inserted, didReachMax: true, newStartingIndex: nextIndex)
            return CMTypes.PreparationResult(prepared: prepared, result: result, updatedKeys: keys)
        }
    }

    let result = CMTypes.InsertionResult(inserted: inserted, didReachMax: false, newStartingIndex: nextIndex)
    return CMTypes.PreparationResult(prepared: prepared, result: result, updatedKeys: keys)
}

// MARK: - Local helpers

private func parseTitle(in doc: Document, selector: String) -> String? {
    guard !selector.isEmpty,
          let raw = try? doc.select(selector).first()?.text()
    else { return nil }
    let unescaped = (try? Entities.unescape(raw)) ?? raw
    let trimmed = unescaped.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
