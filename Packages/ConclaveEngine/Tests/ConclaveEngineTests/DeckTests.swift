import Foundation
import Testing
@testable import ConclaveEngine

/// The shape `GET /api/decks/{slug}` answers with (cut down), including a card Scryfall didn't know.
let deckJSON = """
{"slug": "meren", "name": "Meren", "commanders": ["Meren of Clan Nel Toth"], "bracket": 3, "version": 12,
 "proxy": false, "currency": "eur", "validation": {"ok": true}, "health": [],
 "cards": [
   {"name": "Sol Ring", "qty": 1, "category": "Ramp"},
   {"name": "Forest", "qty": 9, "category": ""},
   {"name": "Swamp", "qty": 8},
   {"name": "Sakura-Tribe Elder", "category": "Ramp"},
   {"name": "Grave Titan", "category": null},
   {"name": "Mystery Card", "category": "Big Stuff"}
 ],
 "maybe": [{"name": "Craterhoof Behemoth", "category": "Win Condition"}],
 "card_data": {
   "Meren of Clan Nel Toth": {"type_line": "Legendary Creature — Human Shaman", "mana_cost": "{2}{B}{G}", "cmc": 4,
     "price_eur": 1.5, "image": "https://cards.scryfall.io/normal/front/m.jpg", "color_identity": ["B", "G"]},
   "Sol Ring": {"type_line": "Artifact", "mana_cost": "{1}", "cmc": 1, "price_eur": "2.00", "game_changer": true},
   "Forest": {"type_line": "Basic Land — Forest", "mana_cost": "", "cmc": 0, "price_eur": 0.1},
   "Swamp": {"type_line": "Basic Land — Swamp", "cmc": 0, "price_eur": null},
   "Sakura-Tribe Elder": {"type_line": "Creature — Snake Shaman", "mana_cost": "{1}{G}", "cmc": 2, "price_eur": 0.3},
   "Grave Titan": {"type_line": "Creature — Giant", "mana_cost": "{4}{B}{B}", "cmc": 6, "price_eur": 4,
     "image": "javascript:alert(1)"},
   "Craterhoof Behemoth": {"type_line": "Creature — Beast", "cmc": 8, "price_eur": 30}
 }}
"""

@Suite struct DeckTests {
    func meren() throws -> Deck { try JSONDecoder().decode(Deck.self, from: Data(deckJSON.utf8)) }

    @Test func readsTheDeck() async throws {
        let transport = FakeTransport(body: deckJSON)
        let deck = try await EngineClient(address: address, transport: transport).deck("meren")
        #expect(transport.requests.first?.url?.path == "/api/decks/meren")
        #expect(deck.cards.count == 6 && deck.maybe.count == 1)
        #expect(deck.cards[1].category == nil)  // "" means no category
        #expect(deck.cards[3].qty == 1)
        #expect(deck.cardData["Sol Ring"]?.priceEur == 2)  // a price as a string
        #expect(deck.cardData["Sol Ring"]?.gameChanger == true)
        #expect(deck.cardData["Meren of Clan Nel Toth"]?.image?.host == "cards.scryfall.io")
        #expect(deck.cardData["Grave Titan"]?.image == nil)  // only http(s) links
    }

    @Test func countsAndPricesLikeTheEngine() throws {
        let deck = try meren()
        #expect(deck.cardCount == 1 + 1 + 9 + 8 + 1 + 1 + 1)  // commander included, the maybe list not
        #expect(deck.price == 1.5 + 2 + 0.9 + 0.3 + 4)  // no price for Swamp and the unknown card, none for maybe
    }

    @Test func groupsByCategoryLikeTheWebApp() throws {
        let sections = try meren().sections(by: .category)
        #expect(sections.map(\.key) == [.commander, .category("Ramp"), .category("Land"), .type(.creature),
                                         .category("Big Stuff"), .maybe])
        #expect(sections[1].rows.map(\.name) == ["Sakura-Tribe Elder", "Sol Ring"])
        #expect(sections[2].count == 17)
        #expect(sections[0].rows.first?.isCommander == true)
        #expect(sections.last?.rows.first?.onMaybeList == true)
    }

    @Test func aCustomCategoryComesAfterTheKnownOnes() throws {
        let deck = try JSONDecoder().decode(Deck.self, from: Data("""
        {"slug": "x", "cards": [{"name": "A", "category": "Zombies"}, {"name": "B", "category": "Draw"},
                                {"name": "C", "category": "Aristocrats"}]}
        """.utf8))
        #expect(deck.sections(by: .category).map(\.key) == [.category("Draw"), .category("Aristocrats"),
                                                            .category("Zombies")])
    }

    @Test func groupsByTypeAndManaValue() throws {
        let deck = try meren()
        #expect(deck.sections(by: .type).map(\.key) == [.commander, .type(.creature), .type(.artifact), .type(.land),
                                                        .type(.other), .maybe])  // the unknown card has no type
        #expect(deck.sections(by: .manaValue).map(\.key) == [.commander, .manaValue(0), .manaValue(1), .manaValue(2),
                                                             .manaValue(6), .type(.land), .maybe])
    }

    @Test func readsTheFrontFaceForTheType() {
        #expect(CardFacts(typeLine: "Artifact Land").cardType == .land)
        #expect(CardFacts(typeLine: "Creature — Human // Land").cardType == .creature)
        #expect(CardFacts(typeLine: "Legendary Planeswalker — Jace").cardType == .planeswalker)
        #expect(CardFacts(typeLine: "Kindred Instant — Elf").cardType == .instant)
        #expect(CardFacts(typeLine: "").cardType == .other)
        #expect(CardFacts(manaValue: 9).manaValue == 9)
    }
}

@Suite struct ManaCostTests {
    @Test func splitsACost() {
        #expect(ManaCost.symbols("{2}{B}{G}") == ["2", "B", "G"])
        #expect(ManaCost.symbols("{X}{w/u}{G/P}") == ["X", "W/U", "G/P"])
        #expect(ManaCost.symbols("{1}{G} // {3}") == ["1", "G", "3"])
        #expect(ManaCost.symbols("") == [])
        #expect(ManaCost.symbols("{}{") == [])
    }

    @Test func picksTheColour() {
        #expect(ManaCost.color(of: "B") == "B")
        #expect(ManaCost.color(of: "2/W") == "W")
        #expect(ManaCost.color(of: "G/P") == "G")
        #expect(ManaCost.color(of: "12") == nil)
        #expect(ManaCost.color(of: "C") == nil)
    }
}
