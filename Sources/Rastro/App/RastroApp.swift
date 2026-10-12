import AppKit
import SwiftUI

@main
struct RastroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: AppStore

    init() {
        // Antes de abrir o banco: traz os dados do tempo em que o app se chamava Dev Timeline.
        if !DemoMode.isOn { LegacyMigration.run() }
        _store = State(initialValue: AppStore.shared)
    }

    var body: some Scene {
        WindowGroup("Rastro") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(store)
                .defaultAppStorage(AppSettings.defaults)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            DeployCommands()
            CommandGroup(after: .newItem) {
                Button("Nota rápida") { QuickNoteController.shared.show() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .defaultAppStorage(AppSettings.defaults)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var quickNoteHotKey: GlobalHotKey?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prints do README: desenha as telas fora da tela e fecha.
        if let folder = Snapshots.outputFolder {
            NSApp.setActivationPolicy(.accessory)
            NSApp.windows.forEach { $0.close() }
            Snapshots.run(into: folder)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        // Demonstração: só os dados fictícios, sem escanear pastas nem registrar atalho global.
        guard !DemoMode.isOn else { return }
        AppStore.shared.startAutoScan()

        quickNoteHotKey = GlobalHotKey.quickNote { QuickNoteController.shared.toggle() }
        if quickNoteHotKey == nil {
            AppStore.shared.shortcutWarning = "⌥⌘N já é usado por outro app. Use Arquivo > Nota rápida."
        }
    }
}
