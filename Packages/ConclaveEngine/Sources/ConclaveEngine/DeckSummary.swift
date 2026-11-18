import Foundation

/// One deck in the deck list (`GET /api/decks`, `storage.list_decks()` in Conclave).
/// Every key but `slug` is optional on purpose: a damaged deck file comes with only a few of them,
/// and an older engine may lack newer ones.
public struct DeckSummary: Decodable, Sendable, Equatable, Identifiable {
    public var id: String { slug }
    public let slug: String
    public let name: String
    public let commanders: [String]
    public let bracket: Int?
    /// The engine's short level text (German for now, e.g. "Bracket 3 · Mittel").
    public let level: String
    public let proxy: Bool
    /// When it was last saved, as the engine wrote it (ISO 8601).
    public let updated: Date?
    public let version: Int?
    /// nil = never checked.
    public let valid: Bool?
    public let colorIdentity: [String]
    /// Legal and meets its target bracket.
    public let fits: Bool
    /// Changed on another device; the next check is still to come.
    public let needsRevalidation: Bool
    public let pinned: Bool
    public let shelved: Bool
    public let planning: Bool
    public let built: Bool
    public let damaged: Bool

    enum CodingKeys: String, CodingKey {
        case slug, name, commanders, bracket, level, proxy, updated, version, valid, fits, pinned, shelved, planning,
            built, damaged
        case colorIdentity = "color_identity"
        case needsRevalidation = "needs_revalidation"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? slug
        commanders = (try? c.decodeIfPresent([String].self, forKey: .commanders)) ?? []
        bracket = try? c.decodeIfPresent(Int.self, forKey: .bracket)
        level = (try? c.decodeIfPresent(String.self, forKey: .level)) ?? ""
        proxy = (try? c.decodeIfPresent(Bool.self, forKey: .proxy)) ?? false
        updated = (try? c.decodeIfPresent(String.self, forKey: .updated)).flatMap(Self.date)
        version = try? c.decodeIfPresent(Int.self, forKey: .version)
        valid = try? c.decodeIfPresent(Bool.self, forKey: .valid)
        colorIdentity = (try? c.decodeIfPresent([String].self, forKey: .colorIdentity)) ?? []
        fits = (try? c.decodeIfPresent(Bool.self, forKey: .fits)) ?? false
        needsRevalidation = (try? c.decodeIfPresent(Bool.self, forKey: .needsRevalidation)) ?? false
        pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
        shelved = (try? c.decodeIfPresent(Bool.self, forKey: .shelved)) ?? false
        planning = (try? c.decodeIfPresent(Bool.self, forKey: .planning)) ?? false
        built = (try? c.decodeIfPresent(Bool.self, forKey: .built)) ?? false
        damaged = (try? c.decodeIfPresent(Bool.self, forKey: .damaged)) ?? false
    }

    /// Python's `isoformat()`, with or without fractions and a zone (a missing zone counts as UTC).
    static func date(_ text: String) -> Date? {
        var value = text
        if !value.contains("Z"), value.range(of: #"[+-]\d\d:\d\d$"#, options: .regularExpression) == nil {
            value += "Z"
        }
        let plain = ISO8601DateFormatter()
        let fraction = ISO8601DateFormatter()
        fraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: value) ?? fraction.date(from: value)
    }
}

/// The sidebar's groups: pinned decks, the rest, and the paused ones ("Pausiert" on the PC) last.
/// The engine already sorts them; this only splits the list and keeps that order.
public struct DeckGroups: Sendable, Equatable {
    public let pinned: [DeckSummary]
    public let active: [DeckSummary]
    public let paused: [DeckSummary]

    public init(_ decks: [DeckSummary]) {
        pinned = decks.filter { $0.pinned && !$0.shelved }
        active = decks.filter { !$0.pinned && !$0.shelved }
        paused = decks.filter(\.shelved)
    }
}
