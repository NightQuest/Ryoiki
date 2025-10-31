import Foundation

@usableFromInline
internal let defaultUserAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15"

public protocol HTTPClientProtocol: Sendable {
    func get(_ url: URL, referer: URL?) async throws -> (Data, HTTPURLResponse)
    func head(_ url: URL, referer: URL?) async throws -> HTTPURLResponse
    func downloadToTemp(url: URL, referer: URL?) async throws -> (URL, HTTPURLResponse)
}

public enum HTTPClientError: Swift.Error, Sendable {
    case network(Swift.Error)
    case badStatus(Int)
    case cancelled
}

public struct HTTPClient: HTTPClientProtocol {
    private let session: URLSession
    private let rateLimiter: RateLimiter
    private let userAgent: String

    public init() {
        let ua = UserDefaults.standard.string(forKey: .settingsNetworkUserAgent) ?? defaultUserAgent
        let perHost = max(1, UserDefaults.standard.integer(forKey: .settingsNetworkPerHost))
        let config = URLSessionConfiguration.default
        // Be gentle to servers; align with download concurrency
        config.httpMaximumConnectionsPerHost = perHost
        // Enable a small cache to avoid re-fetching pages that are cacheable
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,   // 16 MB
            diskCapacity: 128 * 1024 * 1024,    // 128 MB
            diskPath: "RyoikiURLCache"
        )
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config)
        self.init(session: session, userAgent: ua)
    }

    @usableFromInline
    internal static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        // Be gentle to servers; align with download concurrency
        config.httpMaximumConnectionsPerHost = 6
        // Enable a small cache to avoid re-fetching pages that are cacheable
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,   // 16 MB
            diskCapacity: 128 * 1024 * 1024,    // 128 MB
            diskPath: "RyoikiURLCache"
        )
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    @usableFromInline
    internal static func makeBackgroundSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        // Align with polite defaults; mirror makeDefaultSession where appropriate
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "RyoikiURLCache"
        )
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    public init(session: URLSession = HTTPClient.makeDefaultSession(), userAgent: String = defaultUserAgent) {
        self.session = session
        self.rateLimiter = .shared
        self.userAgent = userAgent
    }

    public init(userAgent: String) {
        self.session = HTTPClient.makeDefaultSession()
        self.rateLimiter = .shared
        self.userAgent = userAgent
    }

    init(session: URLSession, rateLimiter: RateLimiter, userAgent: String = defaultUserAgent) {
        self.session = session
        self.rateLimiter = rateLimiter
        self.userAgent = userAgent
    }

    // MARK: - Public API

    public func get(_ url: URL, referer: URL? = nil) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await request(url: url, method: "GET", referer: referer)
        } catch let clientError as HTTPClientError {
            throw clientError
        } catch {
            throw mapNetworkError(error)
        }
    }

    public func head(_ url: URL, referer: URL? = nil) async throws -> HTTPURLResponse {
        do {
            let (_, response) = try await request(url: url, method: "HEAD", referer: referer)
            return response
        } catch let clientError as HTTPClientError {
            throw clientError
        } catch {
            throw mapNetworkError(error)
        }
    }

    public func downloadToTemp(url: URL, referer: URL? = nil) async throws -> (URL, HTTPURLResponse) {
        await rateLimiter.acquire(for: url)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        do {
            let (tempURL, response) = try await session.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPClientError.network(URLError(.badServerResponse))
            }
            return (tempURL, httpResponse)
        } catch {
            throw mapNetworkError(error)
        }
    }

    // MARK: - Internals

    private func request(url: URL, method: String, referer: URL?) async throws -> (Data, HTTPURLResponse) {
        await rateLimiter.acquire(for: url)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPClientError.network(URLError(.badServerResponse))
            }
            return (data, httpResponse)
        } catch {
            throw mapNetworkError(error)
        }
    }

    private func mapNetworkError(_ error: Swift.Error) -> HTTPClientError {
        // Treat all forms of cancellation as a cancellable outcome we can ignore upstream.
        if error is CancellationError { return .cancelled }

        // Handle URLSession/URLError cancellation (-999) explicitly.
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .cancelled
        }

        // Bridge to NSError in case the error comes through as Foundation error.
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return .cancelled
        }

        return .network(error)
    }
}
