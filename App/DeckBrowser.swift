import ConclaveEngine
import SwiftUI

/// The sidebar with every deck (pinned, the rest, paused) and the selected deck on the right.
struct DeckBrowser: View {
    @Environment(EngineModel.self) private var engine
    @SceneStorage("selectedDeck") private var selection: String?

    var body: some View {
        NavigationSplitView {
            DeckSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let deck = engine.decks.first(where: { $0.slug == selection }) {
                DeckOverview(deck: deck)
            } else {
                ContentUnavailableView("Pick a Deck", systemImage: "rectangle.stack",
                                       description: Text("Choose a deck in the sidebar."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await engine.reload() } } label: {
                    Label("Reload Decks", systemImage: "arrow.clockwise")
                }
                .help("Reload Decks (⌘R)")
                .disabled(engine.isLoading)
            }
        }
    }
}

struct DeckSidebar: View {
    @Environment(EngineModel.self) private var engine
    @Binding var selection: String?

    var body: some View {
        let groups = DeckGroups(engine.decks)
        List(selection: $selection) {
            if !groups.pinned.isEmpty {
                Section("Pinned") {
                    ForEach(groups.pinned) { DeckRow(deck: $0) }
                }
            }
            Section("Decks") {
                ForEach(groups.active) { DeckRow(deck: $0) }
            }
            if !groups.paused.isEmpty {
                Section("Paused") {
                    ForEach(groups.paused) { DeckRow(deck: $0) }
                }
            }
        }
        .overlay {
            if let error = engine.loadError, engine.decks.isEmpty {
                ContentUnavailableView {
                    Label("Decks Didn't Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message(for: error))
                } actions: {
                    Button("Try Again") { Task { await engine.reload() } }
                }
            } else if engine.decks.isEmpty, !engine.isLoading {
                ContentUnavailableView("No Decks Yet", systemImage: "rectangle.stack",
                                       description: Text("Decks you build on your PC or phone show up here once they sync."))
            }
        }
    }
}

/// One deck in the sidebar: name, commanders, and a red dot when it isn't legal (like the Windows sidebar).
struct DeckRow: View {
    let deck: DeckSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.name)
                    .lineLimit(1)
                if !deck.commanders.isEmpty {
                    Text(deck.commanders.joined(separator: " & "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if deck.damaged || deck.valid == false {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(deck.damaged ? Text("Damaged") : Text("Not legal"))
                    .help(deck.damaged ? Text("The deck file is damaged.") : Text("Not legal"))
            }
        }
        .padding(.vertical, 2)
    }
}

/// The selected deck, for now its head only: the card list and the deck check come in the next steps.
struct DeckOverview: View {
    let deck: DeckSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(deck.name)
                    .font(.largeTitle.bold())
                if !deck.commanders.isEmpty {
                    Text(deck.commanders.joined(separator: " & "))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    if let bracket = deck.bracket {
                        LabeledContent("Bracket", value: "\(bracket)")
                    }
                    if let version = deck.version {
                        LabeledContent("Version", value: "\(version)")
                    }
                    if let updated = deck.updated {
                        LabeledContent("Saved") {
                            Text(updated, format: .relative(presentation: .named))
                        }
                    }
                }
                .font(.callout)
                if deck.needsRevalidation {
                    Label("Changed on another device. The deck check runs again soon.", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .navigationTitle(deck.name)
    }
}
