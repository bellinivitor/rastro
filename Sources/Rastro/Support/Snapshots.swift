import AppKit
import SwiftUI

/// `Rastro.app --demo --snapshot <pasta>`: desenha as telas principais fora da tela, com os dados
/// fictícios, salva um PNG de cada e fecha. Usado nos prints do README; não precisa de permissão
/// de gravação de tela porque nada aparece no monitor.
@MainActor
enum Snapshots {
    /// Verdadeiro só enquanto os prints estão sendo gerados.
    static var isActive: Bool { outputFolder != nil }

    static var outputFolder: URL? {
        let args = CommandLine.arguments
        guard DemoMode.isOn, let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static func run(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task {
            for (screen, title) in [("timeline", "Timeline"), ("stats", "Estatísticas"), ("deploy", "Deploy pendente"), ("standup", "Timeline")] {
                await capture(screen, title: title, into: folder)
            }
            NSApp.terminate(nil)
        }
    }

    private static func capture(_ screen: String, title: String, into folder: URL) async {
        let controller = NSHostingController(
            rootView: ContentView(screen: screen)
                .environment(AppStore.shared)
                .defaultAppStorage(AppSettings.defaults)
        )
        controller.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 1180, height: 760))
        // Bem longe da área visível: a janela existe e é desenhada, mas ninguém a vê.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()

        // Tempo para o SwiftUI montar a tela, a barra de ferramentas e a folha do standup.
        try? await Task.sleep(for: .seconds(1.5))

        let target = window.attachedSheet ?? window
        if let frameView = target.contentView?.superview,
           let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
            frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
            let url = folder.appendingPathComponent("\(screen).png")
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.attachedSheet.map { window.endSheet($0) }
        window.orderOut(nil)
        window.close()
    }
}
