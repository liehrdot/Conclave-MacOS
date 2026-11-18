import AppKit
import ConclaveEngine
import SwiftUI

/// The app: one main window with the deck sidebar, the Settings window (⌘,) and the menu commands.
@main
struct ConclaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var engine = EngineModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .frame(minWidth: 760, minHeight: 480)
        }
        .commands { DeckCommands(engine: engine) }

        Settings {
            SettingsView()
                .environment(engine)
        }
    }
}

/// Starts the engine with the app and stops it before the app quits, so no engine is left running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        EngineModel.shared.start()
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let unsaved = EngineModel.shared.unsavedDecks.count
        if unsaved > 0 {
            let alert = NSAlert()
            alert.messageText = String(localized: "Quit without saving your deck changes?")
            alert.informativeText = String(localized: "Changes to \(unsaved) decks aren't saved yet. They're lost when Conclave quits.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.addButton(withTitle: String(localized: "Quit Anyway"))
            if alert.runModal() != .alertSecondButtonReturn { return .terminateCancel }
        }
        Task {
            await EngineModel.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// The app's own menu items: File › Save (⌘S) for the deck in the front window, and ⌘R to reload the deck list
/// (the Windows app refreshes on its own after a sync; the Mac app will too once sync status arrives here).
struct DeckCommands: Commands {
    let engine: EngineModel
    @FocusedValue(\.deckEditor) private var editor

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                if let editor { Task { await engine.save(editor) } }
            }
            .keyboardShortcut("s")
            .disabled(editor?.hasChanges != true || editor?.isSaving == true)
        }
        CommandGroup(before: .toolbar) {
            Button("Reload Decks") { Task { await engine.reload() } }
                .keyboardShortcut("r")
                .disabled(engine.client == nil)
            Divider()
        }
    }
}
