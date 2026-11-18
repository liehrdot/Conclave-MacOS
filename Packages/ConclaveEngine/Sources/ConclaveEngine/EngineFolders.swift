import Foundation

/// The folders the engine works in. They are the same ones Conclave's `paths.py` uses on a Mac when packaged
/// (`~/Library/Application Support/MTG Deckbuilder`, `~/Library/Caches/MTG Deckbuilder`; the old name on purpose,
/// like the Windows data folder), so decks, collection and sync state stay where the engine expects them.
public struct EngineFolders: Sendable, Equatable {
    public static let dataFolderName = "MTG Deckbuilder"

    public let data: URL
    public let cache: URL

    public init(data: URL, cache: URL) {
        self.data = data
        self.cache = cache
    }

    /// The engine's log of the current run; the one before is kept as `backend.1.log`.
    public var log: URL { data.appending(path: "logs/backend.log") }
    public var previousLog: URL { data.appending(path: "logs/backend.1.log") }

    /// The folders for this user. `MTG_HOME` / `MTG_CACHE_HOME` win, like in the engine itself (for development).
    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> EngineFolders {
        let library = home.appending(path: "Library")
        let data = environment["MTG_HOME"].map { URL(filePath: $0) }
            ?? library.appending(path: "Application Support/\(dataFolderName)")
        let cache = environment["MTG_CACHE_HOME"].map { URL(filePath: $0) }
            ?? library.appending(path: "Caches/\(dataFolderName)")
        return EngineFolders(data: data, cache: cache)
    }

    /// The arguments the engine starts with (Conclave's `launch.py`): its folders, a free port, a fresh token.
    public var arguments: [String] {
        ["--data", data.path, "--cache", cache.path, "--port", "0", "--token", "auto"]
    }
}
