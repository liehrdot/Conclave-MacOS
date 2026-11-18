import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one request. The app uses `URLSessionTransport`; tests use a fake.
public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// A plain `URLSession` without a URL cache or cookies: the engine is on this Mac, every answer is fresh,
/// and the token goes in the `Authorization` header, never a cookie.
public struct URLSessionTransport: Transport {
    let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 120  // a deck check asks Scryfall and Spellbook
        session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineError.badAnswer }
        return (data, http)
    }
}

/// What can go wrong talking to the engine. The app turns these into sentences in the user's language.
public enum EngineError: Error, Equatable, Sendable {
    /// The engine refused the token (it restarted with a new one).
    case unauthorized
    /// Not found (a deck someone deleted on another device).
    case notFound
    /// The engine said no, with its own message (`detail` in FastAPI's error body).
    case refused(status: Int, message: String?)
    /// The answer was not what we expected.
    case badAnswer
}

/// Calls the engine's JSON API (the routes Conclave's web GUI uses, `gui/app.py`).
public struct EngineClient: Sendable {
    public let address: EngineAddress
    let transport: Transport
    /// The user's languages in order, sent as `Accept-Language` so the engine can answer in them.
    let languages: [String]

    public init(address: EngineAddress, transport: Transport = URLSessionTransport(), languages: [String] = Locale.preferredLanguages) {
        self.address = address
        self.transport = transport
        self.languages = languages
    }

    /// Readiness and version (`GET /api/health`, open without the token).
    public func health() async throws -> EngineHealth {
        try await get("api/health")
    }

    /// Every deck, in the engine's order: pinned first, paused last (`storage.list_decks()`).
    public func decks() async throws -> [DeckSummary] {
        try await get("api/decks")
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(request("GET", path, query: query))
    }

    func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: address.url(path, query: query))
        request.httpMethod = method
        request.setValue("Bearer \(address.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.acceptLanguage(languages), forHTTPHeaderField: "Accept-Language")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300:
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw EngineError.badAnswer }
        case 401: throw EngineError.unauthorized
        case 404: throw EngineError.notFound
        default: throw EngineError.refused(status: response.statusCode, message: Self.detail(data))
        }
    }

    /// FastAPI's `{"detail": "…"}`, when it is a sentence (a validation error is a list instead).
    static func detail(_ data: Data) -> String? {
        struct Body: Decodable { let detail: String }
        return (try? JSONDecoder().decode(Body.self, from: data))?.detail
    }

    /// `de-DE, en;q=0.9, …` from the user's languages, at most five.
    static func acceptLanguage(_ languages: [String]) -> String {
        let picked = languages.prefix(5)
        guard !picked.isEmpty else { return "en" }
        return picked.enumerated().map { index, tag in
            index == 0 ? tag : "\(tag);q=\(String(format: "%.1f", 1.0 - Double(index) * 0.1))"
        }.joined(separator: ", ")
    }
}

/// `GET /api/health`.
public struct EngineHealth: Decodable, Sendable, Equatable {
    public let ok: Bool
    public let version: String
    public let frozen: Bool

    enum CodingKeys: CodingKey { case ok, version, frozen }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decode(Bool.self, forKey: .ok)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        frozen = try c.decodeIfPresent(Bool.self, forKey: .frozen) ?? false
    }
}
