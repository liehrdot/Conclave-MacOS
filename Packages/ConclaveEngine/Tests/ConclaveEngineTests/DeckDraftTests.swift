import Foundation
import Testing
@testable import ConclaveEngine

@Suite struct DeckDraftTests {
    func meren() throws -> Deck { try JSONDecoder().decode(Deck.self, from: Data(deckJSON.utf8)) }

    @Test func noEditsNoChanges() throws {
        let deck = try meren()
        #expect(DeckDraft(deck).changes(from: deck) == nil)
    }

    @Test func addsRemovesAndCounts() throws {
        let deck = try meren()
        var draft = DeckDraft(deck)
        let added = draft.add("Mind Stone")
        let basic = draft.add("Forest")  // one more basic
        let commander = draft.add("Meren of Clan Nel Toth")  // the commander stays where it is
        #expect(added && basic && !commander)
        draft.remove("Grave Titan")
        draft.setQuantity("Swamp", 6)
        draft.setCategory("Sol Ring", "Utility")
        let changes = try #require(draft.changes(from: deck))
        #expect(changes.add == [.init(name: "Mind Stone", qty: 1, category: nil)])
        #expect(changes.remove == ["Grave Titan"])
        #expect(changes.setQty == ["Forest": 10, "Swamp": 6])
        #expect(changes.setCategory == ["Sol Ring": "Utility"])
        #expect(changes.count == 5)
    }

    @Test func zeroCopiesTakesTheCardOut() throws {
        let deck = try meren()
        var draft = DeckDraft(deck)
        draft.setQuantity("Sol Ring", 0)
        #expect(!draft.contains("Sol Ring"))
        #expect(draft.changes(from: deck)?.remove == ["Sol Ring"])
    }

    @Test func undoingByHandLeavesNoChanges() throws {
        let deck = try meren()
        var draft = DeckDraft(deck)
        draft.setQuantity("Swamp", 3)
        draft.setQuantity("Swamp", 8)
        draft.add("Mind Stone")
        draft.remove("Mind Stone")
        #expect(draft.changes(from: deck) == nil)
    }

    @Test func movesBetweenTheDeckAndTheMaybeList() throws {
        let deck = try meren()
        var draft = DeckDraft(deck)
        draft.moveToMaybe("Sakura-Tribe Elder")  // a deck card: the engine moves it itself
        draft.add("Craterhoof Behemoth")  // from the list into the deck, keeping its category
        draft.moveToMaybe("Avenger of Zendikar")  // a new card straight onto the list
        #expect(draft.onMaybeList("Sakura-Tribe Elder") && !draft.contains("Sakura-Tribe Elder"))
        #expect(draft.cards.first { $0.name == "Craterhoof Behemoth" }?.category == "Win Condition")
        let changes = try #require(draft.changes(from: deck))
        #expect(changes.remove.isEmpty)
        #expect(changes.maybeAdd.map(\.name) == ["Sakura-Tribe Elder", "Avenger of Zendikar"])
        #expect(changes.maybeAdd.first?.category == "Ramp")
        #expect(changes.add.map(\.name) == ["Craterhoof Behemoth"])
        #expect(changes.maybeRemove.isEmpty)  // the engine takes an added card off the list by itself
    }

    @Test func removingFromTheMaybeList() throws {
        let deck = try meren()
        var draft = DeckDraft(deck)
        draft.remove("Craterhoof Behemoth")
        #expect(draft.changes(from: deck) == DeckChanges(maybeRemove: ["Craterhoof Behemoth"]))
    }

    @Test func encodesWhatTheEngineTakes() throws {
        var changes = DeckChanges()
        changes.add = [.init(name: "Mind Stone", qty: 1, category: nil)]
        changes.setQty = ["Swamp": 6]
        changes.maybeAdd = [.init(name: "X", category: "Ramp")]
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changes)) as? [String: Any]
        #expect(Set(json?.keys.map { $0 } ?? []) == ["add", "remove", "set_qty", "set_category", "maybe_add", "maybe_remove"])
        #expect((json?["set_qty"] as? [String: Int]) == ["Swamp": 6])
    }

    @Test func showsTheDraft() throws {
        let deck = try meren()
        var draft = DeckDraft(deck)
        draft.add("Mind Stone")
        let shown = deck.applying(draft, facts: ["Mind Stone": CardFacts(typeLine: "Artifact", manaValue: 2)])
        #expect(shown.cardCount == deck.cardCount + 1)
        #expect(shown.cardData["Mind Stone"]?.cardType == .artifact)
        #expect(shown.sections(by: .type).contains { $0.rows.contains { $0.name == "Mind Stone" } })
    }

    @Test func savesAndLooksUp() async throws {
        let saved = FakeTransport(body: #"{"slug": "meren", "version": 13, "change_note": "Manuell: + Mind Stone", "legal": true, "errors": [], "warnings": [], "card_count": 100}"#)
        var changes = DeckChanges()
        changes.add = [.init(name: "Mind Stone", qty: 1, category: nil)]
        let answer = try await EngineClient(address: address, transport: saved).save(changes, to: "meren")
        #expect(answer.version == 13 && answer.legal && answer.changeNote == "Manuell: + Mind Stone")
        #expect(saved.requests.first?.httpMethod == "POST" && saved.requests.first?.url?.path == "/api/decks/meren/cards")

        let card = FakeTransport(body: #"{"name": "Rampant Growth", "type_line": "Sorcery", "mana_cost": "{1}{G}", "cmc": 2, "choices": [{"name": "Rampant Growth"}, {"name": "Studious First-Year // Rampant Growth"}]}"#)
        let found = try await EngineClient(address: address, transport: card).card(named: "Rampant Growth")
        #expect(found.name == "Rampant Growth" && found.facts.cardType == .sorcery)
        #expect(found.choices == ["Rampant Growth", "Studious First-Year // Rampant Growth"])
        #expect(card.requests.first?.url?.query?.contains("choices=1") == true)

        let names = FakeTransport(body: #"["Sol Ring", "Solemn Simulacrum"]"#)
        #expect(try await EngineClient(address: address, transport: names).autocomplete("Sol") == ["Sol Ring", "Solemn Simulacrum"])
    }
}
