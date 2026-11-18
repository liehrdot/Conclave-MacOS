import Foundation
import Testing
@testable import ConclaveEngine

@Suite struct CardDatabaseTests {
    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func readsAFreshDatabase() throws {
        let db = try decode(CardDatabase.self, """
        {"available": true, "path": "/x/cards.sqlite", "cards": 31245, "tagged_cards": 29000, "tags": 5100,
         "languages": ["de", "en", "fr"], "cards_bulk_type": "all_cards",
         "cards_updated_at": "2026-11-18T09:12:44.123+00:00", "last_refresh": "2026-11-18T10:00:00Z",
         "schema_outdated": false, "needs_refresh": false, "bulk_type": "all_cards"}
        """)
        #expect(db.available && db.cards == 31245 && db.tags == 5100 && db.languages == 3)
        #expect(db.updated != nil)
        #expect(db.advice == .none)
    }

    @Test func adviseDownloadOrUpdate() throws {
        // a Mac without a database: the engine sends only these keys
        let missing = try decode(CardDatabase.self, #"{"available": false, "path": "/x", "needs_refresh": true}"#)
        #expect(missing.advice == .download && missing.cards == 0 && missing.updated == nil)
        let old = try decode(CardDatabase.self, #"{"available": true, "cards": 9, "needs_refresh": true}"#)
        #expect(old.advice == .update)
        let olderEngine = try decode(CardDatabase.self, #"{"available": true, "needs_refresh": false, "schema_outdated": true}"#)
        #expect(olderEngine.advice == .update)
    }

    @Test func readsTheRun() throws {
        #expect(try decode(CardDatabaseRun.self, #"{"running": false}"#) == CardDatabaseRun(running: false))
        #expect(try decode(CardDatabaseRun.self, #"{"running": true}"#).running)
        #expect(try decode(CardDatabaseRun.self, #"{"running": false, "error": "keine Verbindung"}"#).error == "keine Verbindung")
        #expect(try decode(CardDatabaseRun.self, #"{"running": false, "error": null}"#).error == nil)
    }

    @Test func startsADownload() async throws {
        let transport = FakeTransport(body: #"{"started": true}"#)
        try await EngineClient(address: address, transport: transport).refreshCardDatabase()
        #expect(transport.requests.first?.httpMethod == "POST")
        #expect(transport.requests.first?.url?.path == "/api/carddb/refresh")
    }
}
