import Foundation

/// The engine's local card database (`GET /api/carddb`, `carddb.status()` in Conclave): Scryfall's bulk data in
/// SQLite, so the engine looks cards up on this Mac instead of asking Scryfall card by card.
public struct CardDatabase: Decodable, Sendable, Equatable {
    public let available: Bool
    public let cards: Int
    public let tags: Int
    public let languages: Int
    /// When Scryfall made the bulk file it was built from.
    public let updated: Date?
    /// Older than `MTG_BULK_MAX_AGE_DAYS`, or built by an older engine.
    public let needsRefresh: Bool
    /// Built by an older engine that didn't keep some card facts yet (back faces, tokens).
    public let schemaOutdated: Bool

    enum CodingKeys: String, CodingKey {
        case available, cards, tags, languages
        case updated = "cards_updated_at"
        case needsRefresh = "needs_refresh"
        case schemaOutdated = "schema_outdated"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = (try? c.decodeIfPresent(Bool.self, forKey: .available)) ?? false
        cards = (try? c.decodeIfPresent(Int.self, forKey: .cards)) ?? 0
        tags = (try? c.decodeIfPresent(Int.self, forKey: .tags)) ?? 0
        languages = ((try? c.decodeIfPresent([String].self, forKey: .languages)) ?? nil)?.count ?? 0
        updated = (try? c.decodeIfPresent(String.self, forKey: .updated)).flatMap { DeckSummary.date($0) }
        needsRefresh = (try? c.decodeIfPresent(Bool.self, forKey: .needsRefresh)) ?? !available
        schemaOutdated = (try? c.decodeIfPresent(Bool.self, forKey: .schemaOutdated)) ?? false
    }

    /// What the app suggests: download it, update it, or nothing.
    public enum Advice: Sendable, Equatable { case download, update, none }

    public var advice: Advice {
        if !available { return .download }
        return needsRefresh || schemaOutdated ? .update : .none
    }
}

/// The download running in the engine (`GET /api/carddb/refresh`): it says only whether it still runs and how the
/// last one ended, no progress.
public struct CardDatabaseRun: Decodable, Sendable, Equatable {
    public let running: Bool
    /// The last run's error, as the engine wrote it.
    public let error: String?

    public init(running: Bool, error: String? = nil) {
        self.running = running
        self.error = error
    }

    enum CodingKeys: CodingKey { case running, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = (try? c.decodeIfPresent(Bool.self, forKey: .running)) ?? false
        error = (try? c.decodeIfPresent(String.self, forKey: .error)).flatMap { $0?.isEmpty == false ? $0 : nil }
    }
}

extension EngineClient {
    public func cardDatabase() async throws -> CardDatabase {
        try await get("api/carddb")
    }

    public func cardDatabaseRun() async throws -> CardDatabaseRun {
        try await get("api/carddb/refresh")
    }

    /// Starts a download (all of Scryfall's cards, about 375 MB, then the import); a running one keeps running.
    public func refreshCardDatabase() async throws {
        struct Started: Decodable {}
        let _: Started = try await send(request("POST", "api/carddb/refresh"))
    }
}
