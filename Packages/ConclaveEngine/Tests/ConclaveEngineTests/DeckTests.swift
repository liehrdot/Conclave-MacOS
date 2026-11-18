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

@Suite struct ManaTests {
    @Test func symbolsAndText() {
        #expect(Mana.pieces("{T}: Add {G}.") == [.symbol(.init("T")), .text(": Add "), .symbol(.init("G")), .text(".")])
        #expect(Mana.pieces("no symbols") == [.text("no symbols")])
        #expect(Mana.pieces("{ broken") == [.text("{ broken")])
        #expect(Mana.pieces("{}{2}") == [.text("{}"), .symbol(.init("2"))])
        #expect(Mana.pieces("{1}{G} // {3}") == [.symbol(.init("1")), .symbol(.init("G")), .text(" // "), .symbol(.init("3"))])
        #expect(Mana.pieces("") == [])
    }

    @Test func kinds() {
        #expect(Mana.Symbol("B").kind == .color("B"))
        #expect(Mana.Symbol("C").kind == .color("C"))
        #expect(Mana.Symbol("10").kind == .generic("10"))
        #expect(Mana.Symbol("X").kind == .generic("X"))
        #expect(Mana.Symbol("B/R").kind == .hybrid("B", "R"))
        #expect(Mana.Symbol("2/W").kind == .hybrid("2", "W"))
        #expect(Mana.Symbol("G/P").kind == .phyrexian("G"))
        #expect(Mana.Symbol("G/U/P").kind == .phyrexian("G"))
        #expect(Mana.Symbol("T").kind == .glyph("T"))
        #expect(Mana.Symbol("w").kind == .color("W"))
    }

    @Test func voiceOverReadsTheNames() {
        #expect(Mana.spoken("{2}{B}{G}") == "2, black, green")
        #expect(Mana.spoken("{T}: Add {C}{C}.") == "tap: Add colorlesscolorless.")
        #expect(Mana.Symbol("2/W").spoken() == "2 or white")
        #expect(Mana.Symbol("R/P").spoken() == "Phyrexian red")
    }

    @Test func voiceOverSpeaksTheAppsLanguage() {
        let german = Mana.Words(names: ["B": "schwarz", "G": "grün", "W": "weiß", "R": "rot"],
                                either: { "\($0) oder \($1)" }, phyrexian: { "phyrexianisch \($0)" })
        #expect(Mana.spoken("{2}{B}{G}", german) == "2, schwarz, grün")
        #expect(Mana.Symbol("2/W").spoken(german) == "2 oder weiß")
        #expect(Mana.Symbol("R/P").spoken(german) == "phyrexianisch rot")
    }
}
