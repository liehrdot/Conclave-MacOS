import Foundation
import Testing
@testable import ConclaveEngine

@Suite struct EngineAddressTests {
    @Test func readsTheLineTheEnginePrints() throws {
        let address = try #require(EngineAddress.parse(line: "MTGDECK_URL=http://127.0.0.1:53817/?token=abc-DEF_1\n"))
        #expect(address.base.absoluteString == "http://127.0.0.1:53817/")
        #expect(address.token == "abc-DEF_1")
    }

    @Test func ignoresEveryOtherLine() {
        #expect(EngineAddress.parse(line: "Conclave GUI: http://127.0.0.1:53817/?token=abc") == nil)
        #expect(EngineAddress.parse(line: "MTGDECK_URL=http://127.0.0.1:53817/") == nil)  // no token
        #expect(EngineAddress.parse(line: "MTGDECK_URL=http://example.com:80/?token=abc") == nil)  // not this Mac
        #expect(EngineAddress.parse(line: "MTGDECK_URL=https://127.0.0.1:80/?token=abc") == nil)
    }

    @Test func buildsAPIURLs() throws {
        let address = try #require(EngineAddress.parse(line: "MTGDECK_URL=http://127.0.0.1:9/?token=t"))
        #expect(address.url("api/decks").absoluteString == "http://127.0.0.1:9/api/decks")
        #expect(address.url("/api/decks/meren", query: [URLQueryItem(name: "a", value: "1")]).absoluteString
            == "http://127.0.0.1:9/api/decks/meren?a=1")
    }
}

@Suite struct RestartPolicyTests {
    @Test func backsOffLikeTheWindowsShellThenGivesUp() {
        var policy = RestartPolicy.standard
        let waits = (0..<6).map { _ in policy.afterExit(ranFor: .seconds(2)) }
        #expect(waits == [.seconds(1), .seconds(2), .seconds(5), .seconds(5), .seconds(5), nil])
    }

    @Test func aLongHealthyRunResetsTheBudget() {
        var policy = RestartPolicy.standard
        for _ in 0..<5 { _ = policy.afterExit(ranFor: .seconds(1)) }
        #expect(policy.afterExit(ranFor: .seconds(600)) == .seconds(1))
    }
}

@Suite struct EngineFoldersTests {
    @Test func usesTheFoldersThePackagedEngineUsesOnAMac() {
        let folders = EngineFolders.standard(home: URL(filePath: "/Users/flo"), environment: [:])
        #expect(folders.data.path == "/Users/flo/Library/Application Support/MTG Deckbuilder")
        #expect(folders.cache.path == "/Users/flo/Library/Caches/MTG Deckbuilder")
        #expect(folders.log.path == "/Users/flo/Library/Application Support/MTG Deckbuilder/logs/backend.log")
        #expect(folders.arguments == [
            "--data", "/Users/flo/Library/Application Support/MTG Deckbuilder",
            "--cache", "/Users/flo/Library/Caches/MTG Deckbuilder", "--port", "0", "--token", "auto",
        ])
    }

    @Test func theEnvironmentWinsForDevelopment() {
        let folders = EngineFolders.standard(
            home: URL(filePath: "/Users/flo"), environment: ["MTG_HOME": "/tmp/h", "MTG_CACHE_HOME": "/tmp/c"])
        #expect(folders.data.path == "/tmp/h")
        #expect(folders.cache.path == "/tmp/c")
    }
}
