//
//  ComicManager+Networking.swift
//  Ryoiki
//

import Foundation

// MARK: - Public Networking Surface
extension ComicManager {
    /// Loads an HTML document as a UTF-8 string using a GET request, applying the configured User-Agent and optional Referer.
    func html(from url: URL, referer: URL? = nil) async throws -> String {
        do {
            let (data, response) = try await http.get(url, referer: referer)

            guard (200..<300).contains(response.statusCode) else { throw Error.badStatus(response.statusCode) }

            var htmlString: String?

            // 1) Honor server-declared encoding if present
            if let textEncoding: String = response.textEncodingName,
               let text = String(data: data, encoding: textEncoding.textEncodingToStringEncoding) {
                htmlString = text
            }

            // 2) Common fast-path fallback: UTF-8
            if htmlString == nil, let text = String(data: data, encoding: .utf8) {
                htmlString = text
            }

            // 3) Heuristic detection using Foundation (platform-agnostic)
            if htmlString == nil {
                var usedLossy: ObjCBool = false
                var converted: NSString?
                let enc = NSString.stringEncoding(
                    for: data,
                    encodingOptions: nil,
                    convertedString: &converted,
                    usedLossyConversion: &usedLossy
                )
                if enc != 0, let s = converted as String? {
                    htmlString = s
                }
            }

            // 4) Last-resort legacy fallbacks
            if htmlString == nil, let text = String(data: data, encoding: .macOSRoman) {
                htmlString = text
            }
            if htmlString == nil, let text = String(data: data, encoding: .ascii) {
                htmlString = text
            }

            guard htmlString != nil else {
                #if DEBUG
                print("Failed to decode HTML for: \(url.absoluteString). Size: \(data.count) bytes")
                #endif
                throw ComicManager.Error.parse
            }

            return htmlString ?? ""
        } catch let clientError as HTTPClientError {
            throw map(clientError)
        }
    }

    func head(_ url: URL, referer: URL? = nil) async throws -> HTTPURLResponse {
        do {
            return try await http.head(url, referer: referer)
        } catch let clientError as HTTPClientError {
            throw map(clientError)
        }
    }

    func getData(_ url: URL, referer: URL? = nil) async throws -> Data {
        do {
            let (data, response) = try await http.get(url, referer: referer)
            guard (200..<300).contains(response.statusCode) else { throw Error.badStatus(response.statusCode) }
            return data
        } catch let clientError as HTTPClientError {
            throw map(clientError)
        }
    }
}
