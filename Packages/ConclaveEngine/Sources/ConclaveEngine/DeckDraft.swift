import Foundation

/// A deck being edited: the cards and the maybe list as they will be once saved. Edits pile up here (with Undo in
/// the app) and go to the engine in one request, so one editing session makes one new version, like the web GUI's
/// pending edits (`edit` in `cardlist.js`) and "Speichern & prüfen".
public struct DeckDraft: Sendable, Equatable {
    public let commanders: [String]
    public private(set) var cards: [DeckCard]
    public private(set) var maybe: [MaybeCard]

    public init(_ deck: Deck) {
        commanders = deck.commanders
        cards = deck.cards
        maybe = deck.maybe
    }

    public func contains(_ name: String) -> Bool { cards.contains { $0.name == name } }
    public func onMaybeList(_ name: String) -> Bool { maybe.contains { $0.name == name } }

    /// Puts a card in the deck: one more copy when it's there already (basic lands), off the maybe list when it was
    /// there (keeping its category). False for a commander.
    @discardableResult
    public mutating func add(_ name: String, category: String? = nil) -> Bool {
        guard !commanders.contains(name) else { return false }
        if let index = cards.firstIndex(where: { $0.name == name }) {
            let card = cards[index]
            cards[index] = DeckCard(name: name, qty: card.qty + 1, category: card.category)
            return true
        }
        let fromMaybe = maybe.first { $0.name == name }
        maybe.removeAll { $0.name == name }
        cards.append(DeckCard(name: name, qty: 1, category: category ?? fromMaybe?.category))
        return true
    }

    /// The number of copies; 0 or less takes the card out.
    public mutating func setQuantity(_ name: String, _ qty: Int) {
        guard let index = cards.firstIndex(where: { $0.name == name }) else { return }
        if qty <= 0 {
            cards.remove(at: index)
        } else {
            cards[index] = DeckCard(name: name, qty: min(qty, 99), category: cards[index].category)
        }
    }

    public mutating func remove(_ name: String) {
        cards.removeAll { $0.name == name }
        maybe.removeAll { $0.name == name }
    }

    public mutating func setCategory(_ name: String, _ category: String) {
        if let index = cards.firstIndex(where: { $0.name == name }) {
            cards[index] = DeckCard(name: name, qty: cards[index].qty, category: category)
        }
    }

    /// A deck card moves to the maybe list ("X → Vielleicht"); a new card goes straight onto it.
    public mutating func moveToMaybe(_ name: String) {
        guard !commanders.contains(name), !onMaybeList(name) else { return }
        let category = cards.first { $0.name == name }?.category
        cards.removeAll { $0.name == name }
        maybe.append(MaybeCard(name: name, category: category))
    }

    /// What to send to save the draft (`POST /api/decks/{slug}/cards`), measured against the saved deck; nil when
    /// nothing changed.
    public func changes(from deck: Deck) -> DeckChanges? {
        let before = Dictionary(deck.cards.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let after = Dictionary(cards.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let maybeBefore = Set(deck.maybe.map(\.name))
        let maybeAfter = Set(maybe.map(\.name))
        var out = DeckChanges()
        for card in cards {
            guard let old = before[card.name] else {
                // a card from the maybe list leaves the list by itself when it's added (`maybe.change`)
                out.add.append(.init(name: card.name, qty: card.qty, category: card.category))
                continue
            }
            if old.qty != card.qty { out.setQty[card.name] = card.qty }
            if let category = card.category, category != old.category { out.setCategory[card.name] = category }
        }
        for card in deck.cards where after[card.name] == nil && !maybeAfter.contains(card.name) {
            out.remove.append(card.name)
        }
        // onto the list: new cards and deck cards (the engine moves those itself)
        for card in maybe where !maybeBefore.contains(card.name) {
            out.maybeAdd.append(.init(name: card.name, category: card.category))
        }
        for name in deck.maybe.map(\.name) where !maybeAfter.contains(name) && after[name] == nil {
            out.maybeRemove.append(name)
        }
        return out.isEmpty ? nil : out
    }
}

/// The body of `POST /api/decks/{slug}/cards` (`EditRequest` in Conclave's `gui/app.py`).
public struct DeckChanges: Encodable, Sendable, Equatable {
    public struct Add: Encodable, Sendable, Equatable {
        public let name: String
        public let qty: Int
        public let category: String?
    }

    public struct MaybeAdd: Encodable, Sendable, Equatable {
        public let name: String
        public let category: String?
    }

    public var add: [Add] = []
    public var remove: [String] = []
    public var setQty: [String: Int] = [:]
    public var setCategory: [String: String] = [:]
    public var maybeAdd: [MaybeAdd] = []
    public var maybeRemove: [String] = []

    enum CodingKeys: String, CodingKey {
        case add, remove
        case setQty = "set_qty"
        case setCategory = "set_category"
        case maybeAdd = "maybe_add"
        case maybeRemove = "maybe_remove"
    }

    public var isEmpty: Bool {
        add.isEmpty && remove.isEmpty && setQty.isEmpty && setCategory.isEmpty && maybeAdd.isEmpty && maybeRemove.isEmpty
    }

    /// How many cards change, for "3 changes" next to the deck's name.
    public var count: Int {
        add.count + remove.count + setQty.count + setCategory.count + maybeAdd.count + maybeRemove.count
    }
}

/// The engine's answer to a save (`deckedit.edit_deck()`).
public struct SavedEdit: Decodable, Sendable, Equatable {
    public let version: Int?
    /// "Manuell: + Sol Ring; − Mind Stone", the note the history shows.
    public let changeNote: String
    public let legal: Bool
    public let cardCount: Int?

    enum CodingKeys: String, CodingKey {
        case version, legal
        case changeNote = "change_note"
        case cardCount = "card_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try? c.decodeIfPresent(Int.self, forKey: .version)
        changeNote = (try? c.decodeIfPresent(String.self, forKey: .changeNote)) ?? ""
        legal = (try? c.decodeIfPresent(Bool.self, forKey: .legal)) ?? false
        cardCount = try? c.decodeIfPresent(Int.self, forKey: .cardCount)
    }
}

/// One card looked up by name (`GET /api/card?choices=1`).
public struct CardLookup: Decodable, Sendable, Equatable {
    /// The card's English name, as decks store it (a German name comes back translated).
    public let name: String
    public let facts: CardFacts
    /// Other cards the name can mean (a spell that is also a face of another card), the whole card first; empty
    /// when the name is clear.
    public let choices: [String]

    enum CodingKeys: CodingKey { case name, choices }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        facts = try CardFacts(from: decoder)
        struct Choice: Decodable { let name: String }
        let list = (try? c.decodeIfPresent([Choice].self, forKey: .choices)) ?? nil
        choices = list?.map(\.name) ?? (try? c.decodeIfPresent([String].self, forKey: .choices)) ?? []
    }
}

extension Deck {
    /// The deck as the draft will make it, for showing: cards and maybe list from the draft, facts of newly added
    /// cards from `facts`.
    public func applying(_ draft: DeckDraft, facts: [String: CardFacts] = [:]) -> Deck {
        var out = self
        out.cards = draft.cards
        out.maybe = draft.maybe
        out.cardData.merge(facts) { old, _ in old }
        return out
    }
}

extension EngineClient {
    /// Saves the changes as one new version; the engine checks the deck again (a few seconds).
    public func save(_ changes: DeckChanges, to slug: String) async throws -> SavedEdit {
        let body = try JSONEncoder().encode(changes)
        return try await send(request("POST", "api/decks/\(slug)/cards", body: body))
    }

    /// Card names starting with the typed text (Scryfall's autocomplete through the engine); empty when offline.
    public func autocomplete(_ text: String) async throws -> [String] {
        try await get("api/autocomplete", query: [URLQueryItem(name: "q", value: text)])
    }

    /// One card by name, English or German.
    public func card(named name: String) async throws -> CardLookup {
        try await get("api/card", query: [URLQueryItem(name: "name", value: name), URLQueryItem(name: "choices", value: "1")])
    }
}
