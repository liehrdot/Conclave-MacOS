import Foundation

/// Where the running engine listens and the token it wants. The engine prints one line
/// `MTGDECK_URL=http://127.0.0.1:<port>/?token=<token>` once its socket is bound
/// (Conclave's `gui.serve()`, read the same way by the Windows shell's `backend.rs`).
public struct EngineAddress: Sendable, Equatable {
    /// `http://127.0.0.1:<port>/`, always with a trailing slash so API paths resolve below it.
    public let base: URL
    public let token: String

    public init(base: URL, token: String) {
        self.base = base
        self.token = token
    }

    static let prefix = "MTGDECK_URL="

    /// The address in one line of the engine's output, or nil for every other line.
    public static func parse(line: String) -> EngineAddress? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(prefix),
              let parts = URLComponents(string: String(text.dropFirst(prefix.count))),
              let scheme = parts.scheme, scheme == "http",
              let host = parts.host, ["127.0.0.1", "localhost"].contains(host),
              let port = parts.port,
              let token = parts.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty,
              let base = URL(string: "http://\(host):\(port)/")
        else { return nil }
        return EngineAddress(base: base, token: token)
    }

    /// The URL of an API path such as `api/decks`.
    public func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        parts.path = "/" + path.drop(while: { $0 == "/" })
        if !query.isEmpty { parts.queryItems = query }
        return parts.url!
    }
}
