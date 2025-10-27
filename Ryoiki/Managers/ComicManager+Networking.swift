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
            guard let html = String(data: data, encoding: .utf8) else { throw Error.parse }
            return html
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
