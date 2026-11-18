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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await EngineModel.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// The app's own menu items. ⌘R reloads the deck list (the Windows app refreshes on its own after a sync;
/// the Mac app will too once sync status arrives here).
struct DeckCommands: Commands {
    let engine: EngineModel

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Reload Decks") { Task { await engine.reload() } }
                .keyboardShortcut("r")
                .disabled(engine.client == nil)
            Divider()
        }
    }
}
