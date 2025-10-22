//
//  ComicDownloader.swift
//  Ryoiki
//
//  Created by Stardust on 2025-10-21.
//

import Foundation
import SwiftSoup
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ComicDownloader: Sendable {
    enum Error: Swift.Error {
        case network(Swift.Error)
        case badStatus(Int)
        case parse
        case invalidBaseURL
        case missingSelector(String)
        case cancelled
    }

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15"
    private let session: URLSession
    private let imageExtractor = ImageURLExtractor()

    init(session: URLSession = .shared) { self.session = session }

    // MARK: - Networking

    private func makeRequest(url: URL, method: String, referer: URL?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer = referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.network(NSError(domain: "Invalid response", code: 0))
            }
            return (data, httpResponse)
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// Maps any thrown error into a `ComicDownloader.Error`, preserving cancellation semantics.
    private func mapNetworkError(_ error: Swift.Error) -> ComicDownloader.Error {
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        return .network(error)
    }

    /// Downloads a resource to a temporary file using URLSession.download(for:), applying headers.
    private func downloadToTemp(url: URL, referer: URL?) async throws -> (URL, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer = referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        do {
            let (tempURL, response) = try await session.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.network(NSError(domain: "Invalid response", code: 0))
            }
            return (tempURL, httpResponse)
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// Loads an HTML document as a UTF-8 string using a GET request, applying the configured User-Agent and optional Referer.
    func html(from url: URL, referer: URL? = nil) async throws -> String {
        do {
            let (data, response) = try await makeRequest(url: url, method: "GET", referer: referer)
            guard (200..<300).contains(response.statusCode) else {
                throw Error.badStatus(response.statusCode)
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw Error.parse
            }
            return html
        } catch let scraperError as ComicDownloader.Error {
            // Forward scraper errors as-is (including .cancelled)
            throw scraperError
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// Performs a HEAD request and returns the status code and Content-Type header if present.
    func head(_ url: URL, referer: URL? = nil) async throws -> (status: Int, contentType: String?) {
        do {
            let (_, response) = try await makeRequest(url: url, method: "HEAD", referer: referer)
            let contentType = response.value(forHTTPHeaderField: "Content-Type")
            return (response.statusCode, contentType)
        } catch let scraperError as ComicDownloader.Error {
            // Forward scraper errors as-is (including .cancelled)
            throw scraperError
        } catch {
            throw mapNetworkError(error)
        }
    }

    /// Loads raw data using a GET request, applying the configured User-Agent and optional Referer.
    func getData(_ url: URL, referer: URL? = nil) async throws -> Data {
        do {
            let (data, response) = try await makeRequest(url: url, method: "GET", referer: referer)
            guard (200..<300).contains(response.statusCode) else {
                throw Error.badStatus(response.statusCode)
            }
            return data
        } catch let scraperError as ComicDownloader.Error {
            // Forward scraper errors as-is (including .cancelled)
            throw scraperError
        } catch {
            throw mapNetworkError(error)
        }
    }

    // MARK: - URL Utilities

    private func absoluteURL(_ string: String, base: URL) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    // MARK: - Parsing

    // Parses srcset attribute value into array of (width: Int, url: String)
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

    func fetchPages(
        for comic: Comic,
        context: ModelContext,
        maxPages: Int? = nil
    ) async throws -> Int {
        let firstPage = comic.pages.last?.pageURL ?? comic.firstPageURL
        guard let firstPageURL = URL(string: firstPage
            .trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Error.invalidBaseURL
        }
        let selectorNext = comic.selectorNext
        let selectorImage = comic.selectorImage
        let selectorTitle = comic.selectorTitle

        if selectorImage.isEmpty {
            throw Error.missingSelector("selectorImage")
        }

        var visitedURLs = Set<String>()
        var pagesAdded = 0

        // Find current maximum index in existing pages
        let existingPages = comic.pages.sorted { $0.index < $1.index }
        var currentMaxIndex = existingPages.last?.index ?? -1

        var currentURL = firstPageURL
        var previousURL: URL?

        while true {
            try Task.checkCancellation()
            if let maxPages, pagesAdded >= maxPages { break }
            guard !visitedURLs.contains(currentURL.absoluteString) else { break }
            visitedURLs.insert(currentURL.absoluteString)

            let htmlString = try await fetchHTMLWithRetry(from: currentURL, referer: previousURL)

            let doc: Document
            do {
                doc = try SwiftSoup.parse(htmlString, currentURL.absoluteString)
            } catch {
                throw Error.parse
            }

            let titleText = parseTitle(in: doc, selector: selectorTitle)
            let imageURLs = imageExtractor.extractImageURLs(in: doc, selector: selectorImage, baseURL: currentURL)

            guard !imageURLs.isEmpty else { break }

            let insertion = InsertionContext(comic: comic,
                                             currentURL: currentURL,
                                             startingIndex: currentMaxIndex,
                                             titleText: titleText,
                                             maxPages: maxPages.map { $0 - pagesAdded })

            let result = try insertPages(from: imageURLs,
                                         insertion: insertion,
                                         context: context)
            pagesAdded += result.inserted
            currentMaxIndex = result.newStartingIndex
            if result.didReachMax { break }

            previousURL = currentURL

            if let maxPages, pagesAdded >= maxPages { break }
            if let next = advance(from: currentURL, using: doc, selectorNext: selectorNext, visited: visitedURLs) {
                currentURL = next
            } else {
                break
            }
        }

        return pagesAdded
    }

    @MainActor
    func downloadImages(
        for comic: Comic,
        to folder: URL,
        context: ModelContext,
        overwrite: Bool = false
    ) async throws -> Int {
        let fileManager = FileManager.default
        let comicFolder = folder.appendingPathComponent(sanitizeFilename(comic.name))

        if !fileManager.fileExists(atPath: comicFolder.path) {
            try fileManager.createDirectory(at: comicFolder, withIntermediateDirectories: true)
        }

        let availablePages = comic.pages
            .filter { page in
                page.downloadPath.isEmpty ||
                !fileManager.fileExists(atPath: page.downloadPath)
            }
            .sorted { $0.index < $1.index }

        var filesWritten = 0

        for page in availablePages where try await handlePageDownload(
            page: page,
            comicFolder: comicFolder,
            overwrite: overwrite) {
                filesWritten += 1
        }

        return filesWritten
    }

    @MainActor
    private func handlePageDownload(page: ComicPage, comicFolder: URL, overwrite: Bool) async throws -> Bool {
        let fileManager = FileManager.default

        guard let pageURL = URL(string: page.pageURL) else {
            return false
        }

        let indexPadded = String(format: "%05d", page.index)
        let titlePart: String = page.title.isEmpty ? "" : " - " + sanitizeFilename(page.title)

        // Data URL path
        if page.imageURL.hasPrefix("data:") {
            guard let (mediatype, data) = decodeDataURL(page.imageURL) else { return false }
            let ext = fileExtension(contentType: mediatype, urlExtension: nil, fallback: "png")
            let fileName = "\(indexPadded)\(titlePart).\(ext)"
            let fileURL = comicFolder.appendingPathComponent(fileName)

            if !overwrite && fileManager.fileExists(atPath: fileURL.path) {
                return true
            }

            try data.write(to: fileURL, options: .atomic)
            page.downloadPath = fileURL.absoluteString
            return true
        }

        // Network image path
        guard let imageURL = URL(string: page.imageURL) else { return false }
        let (tempURL, response) = try await downloadToTemp(url: imageURL, referer: pageURL)
        guard (200..<300).contains(response.statusCode) else {
            try? fileManager.removeItem(at: tempURL)
            return false
        }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        let ext = fileExtension(contentType: contentType, urlExtension: imageURL.pathExtension, fallback: "png")

        let fileName = "\(indexPadded)\(titlePart).\(ext)"
        let fileURL = comicFolder.appendingPathComponent(fileName)

        defer { try? fileManager.removeItem(at: tempURL) }

        if !overwrite && fileManager.fileExists(atPath: fileURL.path) {
            return true
        }

        if overwrite && fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }

        try fileManager.moveItem(at: tempURL, to: fileURL)
        page.downloadPath = fileURL.absoluteString
        return true
    }

    private func fileExtension(contentType: String?, urlExtension: String?, fallback: String) -> String {
        if let contentType, let type = UTType(mimeType: contentType), let ext = type.preferredFilenameExtension {
            return ext
        }
        if let urlExtension, !urlExtension.isEmpty { return urlExtension }
        return fallback
    }

    private func sanitizeFilename(_ filename: String) -> String {
        let illegalFileNameCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = filename.components(separatedBy: illegalFileNameCharacters)
        let sanitized = components.joined()
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeDataURL(_ urlString: String) -> (mediatype: String, data: Data)? {
        // data:[<mediatype>][;base64],<data>
        guard urlString.hasPrefix("data:") else {
            return nil
        }
        guard let commaIndex = urlString.firstIndex(of: ",") else {
            return nil
        }

        let meta = String(urlString[urlString.index(urlString.startIndex, offsetBy: 5)..<commaIndex]) // skip "data:"
        let dataPart = String(urlString[urlString.index(after: commaIndex)...])

        let isBase64 = meta.contains(";base64")
        let mediatype = meta.components(separatedBy: ";").first ?? "application/octet-stream"

        if isBase64 {
            guard let data = Data(base64Encoded: dataPart) else {
                return nil
            }
            return (mediatype, data)
        } else {
            guard let decoded = dataPart.removingPercentEncoding,
                  let data = decoded.data(using: .utf8) else {
                return nil
            }
            return (mediatype, data)
        }
    }

    private func parseTitle(in doc: Document, selector: String) -> String? {
        guard !selector.isEmpty else { return nil }
        return (try? doc.select(selector).first()?.text())?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    // MARK: - Navigation

    private func nextLink(in doc: Document, selector: String, baseURL: URL) -> URL? {
        guard !selector.isEmpty else { return nil }
        if let href = try? doc.select(selector).first()?.attr("href") {
            return absoluteURL(href, base: baseURL)
        }
        return nil
    }

    // MARK: - Insertion

    private struct InsertionContext {
        let comic: Comic
        let currentURL: URL
        let startingIndex: Int
        let titleText: String?
        let maxPages: Int?
    }

    private struct InsertionResult {
        let inserted: Int
        let didReachMax: Bool
        let newStartingIndex: Int
    }

    @MainActor
    private func insertPages(from imageURLs: [URL],
                             insertion: InsertionContext,
                             context: ModelContext) throws -> InsertionResult {
        var inserted = 0
        var startingIndex = insertion.startingIndex
        for imageURL in imageURLs where !insertion.comic.pages.contains(where: {
            $0.pageURL == insertion.currentURL.absoluteString &&
            $0.imageURL == imageURL.absoluteString
        }) {
            startingIndex += 1
            let page = ComicPage(
                comic: insertion.comic,
                index: startingIndex,
                title: insertion.titleText ?? "",
                pageURL: insertion.currentURL.absoluteString,
                imageURL: imageURL.absoluteString
            )
            context.insert(page)
            inserted += 1
            if let maxPages = insertion.maxPages, inserted >= maxPages {
                try context.save()
                return InsertionResult(inserted: inserted, didReachMax: true, newStartingIndex: startingIndex)
            }
        }
        if inserted > 0 { try context.save() }
        return InsertionResult(inserted: inserted, didReachMax: false, newStartingIndex: startingIndex)
    }

    // MARK: - Retry

    private func fetchHTMLWithRetry(from url: URL, referer: URL?, attempts: Int = 3) async throws -> String {
        var lastError: Swift.Error?
        for attempt in 0..<max(1, attempts) {
            do {
                return try await html(from: url, referer: referer)
            } catch {
                // Do not retry on cancellation
                if error is CancellationError {
                    throw error
                }
                if let scraperError = error as? ComicDownloader.Error, case .cancelled = scraperError {
                    throw scraperError
                }
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? ComicDownloader.Error.network(NSError(domain: "Unknown", code: -1))
    }

    private func advance(from current: URL, using doc: Document, selectorNext: String, visited: Set<String>) -> URL? {
        guard let next = nextLink(in: doc, selector: selectorNext, baseURL: current) else { return nil }
        guard !visited.contains(next.absoluteString) else { return nil }
        return next
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { self.isEmpty ? nil : self }
}
