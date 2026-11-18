import Foundation

/// One saved deck with its cards (`GET /api/decks/{slug}` in Conclave's `gui/app.py`). Like `DeckSummary`, every key
/// but `slug` may be missing; the engine's extra keys (validation, history, health …) are left for later steps.
public struct Deck: Decodable, Sendable, Equatable, Identifiable {
    public var id: String { slug }
    public let slug: String
    public let name: String
    public let commanders: [String]
    public let cards: [DeckCard]
    /// The "Vielleicht" list: never counted, checked or priced (`maybe.py`).
    public let maybe: [MaybeCard]
    public let bracket: Int?
    public let version: Int?
    public let proxy: Bool
    /// "eur" or "usd": which price the deck counts in.
    public let currency: String
    /// What Scryfall knows about each card, by name (only the keys the web GUI asks for).
    public let cardData: [String: CardFacts]
    /// Set when the engine couldn't look the cards up (offline): the list still shows, without pictures or prices.
    public let cardDataError: String?

    enum CodingKeys: String, CodingKey {
        case slug, name, commanders, cards, maybe, bracket, version, proxy, currency
        case cardData = "card_data"
        case cardDataError = "card_data_error"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? slug
        commanders = (try? c.decodeIfPresent([String].self, forKey: .commanders)) ?? []
        cards = (try? c.decodeIfPresent([DeckCard].self, forKey: .cards)) ?? []
        maybe = (try? c.decodeIfPresent([MaybeCard].self, forKey: .maybe)) ?? []
        bracket = try? c.decodeIfPresent(Int.self, forKey: .bracket)
        version = try? c.decodeIfPresent(Int.self, forKey: .version)
        proxy = (try? c.decodeIfPresent(Bool.self, forKey: .proxy)) ?? false
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "eur"
        cardData = (try? c.decodeIfPresent([String: CardFacts].self, forKey: .cardData)) ?? [:]
        cardDataError = try? c.decodeIfPresent(String.self, forKey: .cardDataError)
    }

    /// Cards in the deck, commanders included (a Commander deck has 100).
    public var cardCount: Int { commanders.count + cards.reduce(0) { $0 + $1.qty } }

    /// What the deck costs at the cheapest printings, commanders included, like `price_total` (nil without prices).
    public var price: Double? {
        let rows = commanders.map { ($0, 1) } + cards.map { ($0.name, $0.qty) }
        let prices = rows.compactMap { name, qty in cardData[name]?.price(currency).map { $0 * Double(qty) } }
        return prices.isEmpty ? nil : prices.reduce(0, +)
    }
}

/// One line of the deck (`deck["cards"]`).
public struct DeckCard: Decodable, Sendable, Equatable {
    public let name: String
    public let qty: Int
    /// The deck's own category (English in the data: "Ramp", "Draw" …); nil = none yet.
    public let category: String?

    enum CodingKeys: CodingKey { case name, qty, category }

    public init(name: String, qty: Int = 1, category: String? = nil) {
        self.name = name
        self.qty = qty
        self.category = category
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        qty = (try? c.decodeIfPresent(Int.self, forKey: .qty)) ?? 1
        category = (try? c.decodeIfPresent(String.self, forKey: .category)).flatMap { $0?.isEmpty == false ? $0 : nil }
    }
}

/// One card on the maybe list (`deck["maybe"]`).
public struct MaybeCard: Decodable, Sendable, Equatable {
    public let name: String
    public let category: String?
}

/// The card facts the engine adds to a deck (`card_data`, from `scryfall.compact()`).
public struct CardFacts: Decodable, Sendable, Equatable {
    public let image: URL?
    /// The back face of a double-faced card.
    public let imageBack: URL?
    public let layout: String?
    public let typeLine: String
    /// "{2}{B}{G}"; "" for lands. A double-faced card has its front's cost.
    public let manaCost: String
    public let manaValue: Double
    public let priceEur: Double?
    public let priceUsd: Double?
    public let gameChanger: Bool
    public let scryfallPage: URL?
    public let colorIdentity: [String]

    enum CodingKeys: String, CodingKey {
        case image, layout, cmc
        case imageBack = "image_back"
        case typeLine = "type_line"
        case manaCost = "mana_cost"
        case priceEur = "price_eur"
        case priceUsd = "price_usd"
        case gameChanger = "game_changer"
        case scryfallPage = "scryfall_uri"
        case colorIdentity = "color_identity"
    }

    public init(typeLine: String = "", manaCost: String = "", manaValue: Double = 0, priceEur: Double? = nil,
                colorIdentity: [String] = []) {
        image = nil
        imageBack = nil
        layout = nil
        self.typeLine = typeLine
        self.manaCost = manaCost
        self.manaValue = manaValue
        self.priceEur = priceEur
        priceUsd = nil
        gameChanger = false
        scryfallPage = nil
        self.colorIdentity = colorIdentity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        image = Self.url(c, .image)
        imageBack = Self.url(c, .imageBack)
        layout = try? c.decodeIfPresent(String.self, forKey: .layout)
        typeLine = (try? c.decodeIfPresent(String.self, forKey: .typeLine)) ?? ""
        manaCost = (try? c.decodeIfPresent(String.self, forKey: .manaCost)) ?? ""
        manaValue = (try? c.decodeIfPresent(Double.self, forKey: .cmc)) ?? 0
        priceEur = Self.number(c, .priceEur)
        priceUsd = Self.number(c, .priceUsd)
        gameChanger = (try? c.decodeIfPresent(Bool.self, forKey: .gameChanger)) ?? false
        scryfallPage = Self.url(c, .scryfallPage)
        colorIdentity = (try? c.decodeIfPresent([String].self, forKey: .colorIdentity)) ?? []
    }

    public func price(_ currency: String) -> Double? { currency == "usd" ? priceUsd : priceEur }

    /// The card type the list groups by: the front face's first match, like the web GUI's `typeOf()`.
    public var cardType: CardType {
        let front = typeLine.components(separatedBy: "//")[0]
        return CardType.allCases.first { $0 != .other && front.contains($0.rawValue) } ?? .other
    }

    /// Only http(s) links: the inspector opens them.
    static func url(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> URL? {
        guard let text = try? c.decodeIfPresent(String.self, forKey: key), let url = URL(string: text),
              ["https", "http"].contains(url.scheme) else { return nil }
        return url
    }

    /// Scryfall's prices come as numbers or as strings ("1.23").
    static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
        return (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { Double($0) }
    }
}

/// Card types in the order the list shows them. Land is checked first, so an artifact land counts as a land.
public enum CardType: String, CaseIterable, Sendable {
    case land = "Land", creature = "Creature", planeswalker = "Planeswalker", battle = "Battle",
        artifact = "Artifact", enchantment = "Enchantment", instant = "Instant", sorcery = "Sorcery", other = "Other"

    /// Where the type's section goes (lands last, like `TYPE_ORDER`).
    var rank: Int {
        switch self {
        case .creature: 1
        case .planeswalker: 2
        case .battle: 3
        case .artifact: 4
        case .enchantment: 5
        case .instant: 6
        case .sorcery: 7
        case .land: 8
        case .other: 9
        }
    }
}
