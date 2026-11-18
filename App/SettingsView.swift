import SwiftUI

/// Settings (⌘,): for now where the data lives and the engine's state.
struct SettingsView: View {
    @Environment(EngineModel.self) private var engine

    var body: some View {
        Form {
            Section("Data") {
                LabeledContent("Data Folder") {
                    Text(engine.folders.data.path)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Show in Finder") { engine.showDataFolder() }
            }
            Section("Card Database") {
                CardDatabaseStatus()
            }
            Section("Engine") {
                LabeledContent("Status", value: status)
                if !engine.version.isEmpty {
                    LabeledContent("Version", value: engine.version)
                }
                Button("Show Log") { engine.showLog() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var status: String {
        switch engine.state {
        case .ready: String(localized: "Running")
        case .starting: String(localized: "Starting…")
        case .failed: String(localized: "Stopped after an error")
        case .stopped: String(localized: "Stopped")
        }
    }
}

/// The card database's state with its one button: Settings shows it, and so does a deck while it loads slowly.
struct CardDatabaseStatus: View {
    @Environment(EngineModel.self) private var engine

    var body: some View {
        let run = engine.cardDatabaseRun
        if run.running {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading and importing Scryfall's cards (about 375 MB). This takes a few minutes.")
            }
        } else {
            if let error = run.error {
                Label("The download didn't work: \(error)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if let database = engine.cardDatabase {
                if database.available {
                    LabeledContent("Cards") { Text(database.cards, format: .number) }
                    if let updated = database.updated {
                        LabeledContent("Updated") { Text(updated, format: .dateTime.day().month().year()) }
                    }
                    if database.advice == .update {
                        Text("An update is recommended.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not downloaded yet. Without it, Conclave looks up every card on Scryfall, which is slower and finds only English names.")
                        .foregroundStyle(.secondary)
                }
                Button(database.available ? "Update Now" : "Download Card Database") {
                    engine.downloadCardDatabase()
                }
                .disabled(engine.client == nil)
            }
        }
    }
}
