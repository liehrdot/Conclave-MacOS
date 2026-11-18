import AppKit
import ConclaveEngine
import Observation

/// The engine as the screens see it: its state, the client to call it with, and the deck list.
/// One for the whole app (`shared`), because there is one engine per Mac user.
@MainActor @Observable
final class EngineModel {
    static let shared = EngineModel()

    private(set) var state: EngineState = .stopped
    private(set) var decks: [DeckSummary] = []
    private(set) var loadError: Error?
    private(set) var isLoading = false
    private(set) var version = ""
    /// No engine inside the app (built without `scripts/build_engine.sh`).
    private(set) var engineMissing = false
    /// The engine's local card database; nil until the engine answered.
    private(set) var cardDatabase: CardDatabase?
    /// Its download, if one runs (the engine reports no progress, only running or not).
    private(set) var cardDatabaseRun = CardDatabaseRun(running: false)

    let folders = EngineFolders.standard()
    @ObservationIgnored private var supervisor: EngineSupervisor?
    /// One URL session for every call, not one per call.
    @ObservationIgnored private let transport = URLSessionTransport()
    @ObservationIgnored private var watching: Task<Void, Never>?
    /// The decks being edited, by slug; an editor stays while its deck has unsaved edits.
    private(set) var editors: [String: DeckEditor] = [:]

    /// The editor for a loaded deck: the existing one gets the newer deck, else a new one starts.
    func editor(for deck: Deck) -> DeckEditor {
        if let editor = editors[deck.slug] {
            editor.update(deck)
            return editor
        }
        let editor = DeckEditor(deck)
        editors[deck.slug] = editor
        return editor
    }

    /// Decks with edits that aren't saved yet (asked about before quitting).
    var unsavedDecks: [DeckEditor] { editors.values.filter(\.hasChanges) }

    /// Saves a deck's edits as one new version, then reloads the deck list (its version and date change).
    func save(_ editor: DeckEditor) async {
        guard let client else { return }
        await editor.save(with: client)
        if editor.saveError == nil { await reload() }
    }

    var client: EngineClient? {
        if case .ready(let address) = state { EngineClient(address: address, transport: transport) } else { nil }
    }

    /// The engine program: `MTGDECK_BACKEND` while developing, else the copy in the app's Contents/Helpers.
    static var executable: URL? {
        if let path = ProcessInfo.processInfo.environment["MTGDECK_BACKEND"] { return URL(filePath: path) }
        let bundled = Bundle.main.bundleURL.appending(path: "Contents/Helpers/conclave-backend/conclave-backend")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }

    func start() {
        guard supervisor == nil else { return }
        guard let executable = Self.executable else {
            engineMissing = true
            state = .failed(reason: "missing", log: "")
            return
        }
        let supervisor = EngineSupervisor(executable: executable, folders: folders) { [weak self] state in
            Task { @MainActor in self?.apply(state) }
        }
        self.supervisor = supervisor
        Task { await supervisor.start() }
    }

    /// "Try Again" after the engine gave up.
    func retry() {
        Task { await supervisor?.start() }
    }

    func stop() async {
        await supervisor?.stop()
    }

    private func apply(_ new: EngineState) {
        state = new
        if case .ready = new {
            Task { await reload() }
            Task { await loadCardDatabase() }
        }
    }

    func reload() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            decks = try await client.decks()
            loadError = nil
            if version.isEmpty { version = (try? await client.health().version) ?? "" }
        } catch {
            loadError = error
        }
    }

    func loadCardDatabase() async {
        guard let client else { return }
        if let database = try? await client.cardDatabase() { cardDatabase = database }
        if let run = try? await client.cardDatabaseRun() {
            cardDatabaseRun = run
            if run.running { watchCardDatabase() }
        }
    }

    /// "Download Card Database" / "Update Now": the engine downloads Scryfall's cards and imports them.
    func downloadCardDatabase() {
        guard let client else { return }
        Task {
            do {
                try await client.refreshCardDatabase()
                cardDatabaseRun = CardDatabaseRun(running: true)
                watchCardDatabase()
            } catch {
                cardDatabaseRun = CardDatabaseRun(running: false, error: message(for: error))
            }
        }
    }

    /// Asks every 5 seconds until the download is over (like the web app's settings), then reads the new state.
    private func watchCardDatabase() {
        guard watching == nil else { return }
        watching = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, let client = self.client else { break }
                guard let run = try? await client.cardDatabaseRun() else { continue }
                self.cardDatabaseRun = run
                if !run.running {
                    if let database = try? await client.cardDatabase() { self.cardDatabase = database }
                    break
                }
            }
            self?.watching = nil
        }
    }

    func showDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([folders.data])
    }

    func showLog() {
        NSWorkspace.shared.activateFileViewerSelecting([folders.log])
    }
}

/// A sentence for an error, in the user's language.
func message(for error: Error) -> String {
    switch error {
    case EngineError.unauthorized:
        String(localized: "Conclave restarted in the background. Try again in a moment.")
    case EngineError.notFound:
        String(localized: "This isn't there any more. It may have been deleted on another device.")
    case EngineError.refused(_, let text?):
        text
    case EngineError.refused(let status, nil):
        String(localized: "Conclave couldn't do that (error \(status)).")
    case EngineError.badAnswer:
        String(localized: "Conclave sent an answer this app doesn't understand.")
    default:
        error.localizedDescription
    }
}
