import ConclaveEngine
import Foundation
import Observation

/// One deck being edited: the deck as the engine saved it, the draft with the pending edits (each one undoable),
/// and the facts of cards added since. Kept per deck in `EngineModel`, so picking another deck keeps the edits.
@MainActor @Observable
final class DeckEditor {
    let slug: String
    /// The deck as the engine has it.
    private(set) var saved: Deck
    private(set) var draft: DeckDraft
    /// Pictures, costs and types of cards added in this session (the saved deck doesn't know them yet).
    private(set) var facts: [String: CardFacts] = [:]
    private(set) var isSaving = false
    /// The window's undo manager; set by the deck screen.
    @ObservationIgnored weak var undoManager: UndoManager?

    init(_ deck: Deck) {
        slug = deck.slug
        saved = deck
        draft = DeckDraft(deck)
    }

    /// The deck as it will be once saved.
    var shown: Deck { saved.applying(draft, facts: facts) }
    var changes: DeckChanges? { draft.changes(from: saved) }
    var hasChanges: Bool { changes != nil }

    /// A newer saved deck (after a save, or a sync); pending edits stay, since the engine applies them to whatever
    /// is saved when they go out.
    func update(_ deck: Deck) {
        saved = deck
        if !hasChanges { draft = DeckDraft(deck) }
    }

    /// One edit, undoable as `action` ("Undo Add Card"). None while a save runs: the save resets the draft.
    func edit(_ action: String, _ change: (inout DeckDraft) -> Void) {
        guard !isSaving else { return }
        let before = draft
        change(&draft)
        guard draft != before else { return }
        registerUndo(back: before, action: action)
    }

    func add(_ card: CardLookup) {
        facts[card.name] = card.facts
        edit(String(localized: "Add Card")) { $0.add(card.name) }
    }

    /// Undo puts the draft back; its own undo (Redo) brings the edit again.
    private func registerUndo(back to: DeckDraft, action: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated {
                let now = editor.draft
                editor.draft = to
                editor.registerUndo(back: now, action: action)
            }
        }
        undoManager.setActionName(action)
    }

    /// Why the last save didn't go through (a card the engine doesn't know, no connection); the edits stay.
    var saveError: String?

    /// Sends the edits as one new version; the engine checks the deck again. On an error the edits stay and
    /// `saveError` says why.
    func save(with client: EngineClient) async {
        guard let changes, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await client.save(changes, to: slug)
        } catch {
            saveError = message(for: error)
            return
        }
        undoManager?.removeAllActions(withTarget: self)
        // saved: until the fresh deck comes (with the new version and the check), show what was sent
        saved = shown
        draft = DeckDraft(saved)
        if let fresh = try? await client.deck(slug) {
            saved = fresh
            draft = DeckDraft(fresh)
            facts = [:]
        }
    }
}
