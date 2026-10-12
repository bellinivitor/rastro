import AppKit
import SwiftUI

@main
struct DevTimelineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore.shared

    var body: some Scene {
        WindowGroup("Dev Timeline") {
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
