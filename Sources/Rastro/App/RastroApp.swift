import AppKit
import SwiftUI

@main
struct RastroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: AppStore

    init() {
        // Antes de abrir o banco: traz os dados do tempo em que o app se chamava Dev Timeline.
        LegacyMigration.run()
        _store = State(initialValue: AppStore.shared)
    }

    var body: some Scene {
        WindowGroup("Rastro") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(store)
        }
        .commands {
            DeployCommands()
            CommandGroup(after: .newItem) {
                Button("Nota rápida") { QuickNoteController.shared.show() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var quickNoteHotKey: GlobalHotKey?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        AppStore.shared.startAutoScan()

        quickNoteHotKey = GlobalHotKey.quickNote { QuickNoteController.shared.toggle() }
        if quickNoteHotKey == nil {
            AppStore.shared.shortcutWarning = "⌥⌘N já é usado por outro app. Use Arquivo > Nota rápida."
        }
    }
}
