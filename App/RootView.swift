import ConclaveEngine
import SwiftUI

/// The main window: the deck browser once the engine runs, else what the engine is doing.
struct RootView: View {
    @Environment(EngineModel.self) private var engine

    var body: some View {
        switch engine.state {
        case .ready:
            DeckBrowser()
        case .failed(_, let log):
            EngineFailedView(log: log, missing: engine.engineMissing)
        case .starting(let attempt):
            StartingView(attempt: attempt)
        case .stopped:
            StartingView(attempt: 0)
        }
    }
}

/// While the engine starts (a few seconds on the first launch, when it opens its card database).
struct StartingView: View {
    let attempt: Int

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            if attempt == 0 {
                Text("Starting Conclave…")
            } else {
                Text("Starting Conclave again (try \(attempt))…")
            }
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The engine gave up: what happened, the end of its log, and the ways out.
struct EngineFailedView: View {
    @Environment(EngineModel.self) private var engine
    let log: String
    let missing: Bool

    var body: some View {
        ContentUnavailableView {
            Label(missing ? "The Engine Is Missing" : "Conclave Couldn't Start", systemImage: "exclamationmark.triangle")
        } description: {
            if missing {
                Text("This copy of the app was built without its engine. Run scripts/build_engine.sh, then build the app again.")
            } else {
                Text("The part of Conclave that checks decks and keeps your data stopped several times in a row.")
            }
        } actions: {
            if !missing {
                Button("Try Again") { engine.retry() }
                    .buttonStyle(.borderedProminent)
                Button("Show Log") { engine.showLog() }
            }
        }
        .overlay(alignment: .bottom) {
            if !log.isEmpty {
                ScrollView {
                    Text(log)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 180)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                .padding(20)
            }
        }
    }
}
