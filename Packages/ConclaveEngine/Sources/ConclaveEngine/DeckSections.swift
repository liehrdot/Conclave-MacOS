import Foundation

/// How the card list is grouped: the web GUI's "Gruppieren nach" (`groupOf()` / `groupRank()` in `cardlist.js`).
public enum DeckGrouping: String, CaseIterable, Sendable {
    case category, type, manaValue
}

/// A section's key; the app turns it into a title in the user's language.
public enum SectionKey: Hashable, Sendable {
    case commander
    /// A deck category as the data stores it ("Ramp", "Board Wipe", or a user's own word).
    case category(String)
    case type(CardType)
    /// Mana value 0 to 6, and 7 for "7+".
    case manaValue(Int)
    case maybe
}

/// One row of the list.
public struct CardRow: Sendable, Equatable, Identifiable {
    public var id: String { (onMaybeList ? "maybe:" : "") + name }
    public let name: String
    public let qty: Int
    public let category: String?
    public let isCommander: Bool
    public let onMaybeList: Bool
    public let facts: CardFacts?
}

public struct DeckSection: Sendable, Equatable, Identifiable {
    public var id: SectionKey { key }
    public let key: SectionKey
    public let rows: [CardRow]
    /// Cards in the section (copies counted).
    public var count: Int { rows.reduce(0) { $0 + $1.qty } }
}

extension Deck {
    /// The categories in the order the web GUI lists them (`CATEGORY_ORDER`); others come after, by name.
    public static let categoryOrder = ["Ramp", "Draw", "Removal", "Board Wipe", "Protection", "Synergy",
                                       "Win Condition", "Utility", "Land"]

    /// The card list in sections: commanders first, the maybe list last, rows by name.
    public func sections(by grouping: DeckGrouping) -> [DeckSection] {
        var groups: [SectionKey: [CardRow]] = [:]
        for card in cards {
            let row = CardRow(name: card.name, qty: card.qty, category: card.category, isCommander: false,
                              onMaybeList: false, facts: cardData[card.name])
            groups[key(for: row, by: grouping), default: []].append(row)
        }
        let byName: (CardRow, CardRow) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var out: [DeckSection] = []
        if !commanders.isEmpty {
            out.append(DeckSection(key: .commander, rows: commanders.map {
                CardRow(name: $0, qty: 1, category: nil, isCommander: true, onMaybeList: false, facts: cardData[$0])
            }))
        }
        out += groups.sorted { Self.rank($0.key) < Self.rank($1.key) }
            .map { DeckSection(key: $0.key, rows: $0.value.sorted(by: byName)) }
        if !maybe.isEmpty {
            out.append(DeckSection(key: .maybe, rows: maybe.map {
                CardRow(name: $0.name, qty: 1, category: $0.category, isCommander: false, onMaybeList: true,
                        facts: cardData[$0.name])
            }.sorted(by: byName)))
        }
        return out
    }

    func key(for row: CardRow, by grouping: DeckGrouping) -> SectionKey {
        let type = row.facts?.cardType ?? .other
        switch grouping {
        case .category:
            if let category = row.category { return .category(category) }
            return type == .land ? .category("Land") : .type(type)
        case .type:
            return .type(type)
        case .manaValue:
            if type == .land { return .type(.land) }
            return .manaValue(min(7, Int((row.facts?.manaValue ?? 0).rounded())))
        }
    }

    /// Sort key for a section: known categories in their order, then types, then other categories by name.
    static func rank(_ key: SectionKey) -> (Int, String) {
        switch key {
        case .commander: (0, "")
        case .category(let name):
            if let index = categoryOrder.firstIndex(of: name) { (1 + index, "") } else { (60, name.lowercased()) }
        case .manaValue(let value): (20 + value, "")
        case .type(let type): (30 + type.rank, "")
        case .maybe: (99, "")
        }
    }
}
