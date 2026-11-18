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
