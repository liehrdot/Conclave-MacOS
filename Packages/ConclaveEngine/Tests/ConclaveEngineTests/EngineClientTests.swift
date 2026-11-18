import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ConclaveEngine

/// Answers every request with one status and body, and remembers what was asked.
final class FakeTransport: Transport, @unchecked Sendable {
    let status: Int
    let body: String
    private let lock = NSLock()
    private var asked: [URLRequest] = []

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = body
    }

    var requests: [URLRequest] { lock.withLock { asked } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { asked.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

let address = EngineAddress(base: URL(string: "http://127.0.0.1:9/")!, token: "secret")

/// The shape `storage.list_decks()` answers with, including a damaged file and a deck from an older engine.
let decksJSON = """
[
  {"slug": "meren", "name": "Meren", "commanders": ["Meren of Clan Nel Toth"], "bracket": 3, "tier": "mid",
   "level": "Bracket 3", "proxy": false, "updated": "2026-11-17T20:15:04", "version": 12, "valid": true,
   "color_identity": ["B", "G"], "fits": true, "table_rule": null, "needs_revalidation": false,
   "pinned": true, "shelved": false, "planning": false, "built": true, "pin_rank": 0},
  {"slug": "krenko", "name": "Krenko", "commanders": ["Krenko, Mob Boss"], "color_identity": "R", "updated": "2026-11-01T10:00:00.123456+00:00",
   "valid": false, "pinned": false, "shelved": false},
  {"slug": "old", "name": "Old Deck", "shelved": true},
  {"slug": "broken", "name": "broken (beschädigt)", "commanders": [], "damaged": true, "level": "", "updated": null,
   "version": null, "valid": false, "fits": false}
]
"""

@Suite struct EngineClientTests {
    @Test func listsDecksAndSendsTheTokenAndLanguages() async throws {
        let transport = FakeTransport(body: decksJSON)
        let client = EngineClient(address: address, transport: transport, languages: ["de-DE", "en-US"])
        let decks = try await client.decks()

        #expect(decks.map(\.slug) == ["meren", "krenko", "old", "broken"])
        let meren = decks[0]
        #expect(meren.commanders == ["Meren of Clan Nel Toth"])
        #expect(meren.bracket == 3 && meren.valid == true && meren.fits && meren.pinned && meren.built)
        #expect(meren.colorIdentity == ["B", "G"])
        #expect(decks[1].colorIdentity == ["R"])  // the engine sends a string
        #expect(meren.updated != nil)
        #expect(decks[1].updated != nil)  // with fractions and a zone
        #expect(decks[1].bracket == nil && decks[1].level == "")
        #expect(decks[3].damaged && decks[3].updated == nil)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:9/api/decks")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "de-DE, en-US;q=0.9")
    }

    @Test func groupsDecksForTheSidebar() async throws {
        let decks = try await EngineClient(address: address, transport: FakeTransport(body: decksJSON)).decks()
        let groups = DeckGroups(decks)
        #expect(groups.pinned.map(\.slug) == ["meren"])
        #expect(groups.active.map(\.slug) == ["krenko", "broken"])
        #expect(groups.paused.map(\.slug) == ["old"])
    }

    @Test func turnsRefusalsIntoErrors() async {
        await #expect(throws: EngineError.unauthorized) {
            try await EngineClient(address: address, transport: FakeTransport(status: 401, body: "{}")).decks()
        }
        await #expect(throws: EngineError.refused(status: 400, message: "Deck nicht gefunden")) {
            try await EngineClient(
                address: address, transport: FakeTransport(status: 400, body: #"{"detail": "Deck nicht gefunden"}"#)
            ).decks()
        }
        await #expect(throws: EngineError.badAnswer) {
            try await EngineClient(address: address, transport: FakeTransport(body: "not json")).decks()
        }
    }

    @Test func readsHealth() async throws {
        let body = #"{"ok": true, "service": "mtgdeck-gui", "version": "0.3.0", "home": "/x", "frozen": true}"#
        let health = try await EngineClient(address: address, transport: FakeTransport(body: body)).health()
        #expect(health.ok && health.frozen && health.version == "0.3.0")
    }

    @Test func acceptLanguageFallsBackToEnglish() {
        #expect(EngineClient.acceptLanguage([]) == "en")
        #expect(EngineClient.acceptLanguage(["en-GB"]) == "en-GB")
    }
}

@Suite struct CancellationTests {
    @Test func tellsACancelledLoadFromAnError() {
        #expect(isCancellation(CancellationError()))
        #expect(isCancellation(URLError(.cancelled)))
        #expect(!isCancellation(URLError(.timedOut)))
        #expect(!isCancellation(EngineError.notFound))
    }
}
