import Foundation

/// `Rastro.app --demo [--screen timeline|stats|deploy|standup]`: abre com dados fictícios, para prints e demonstrações.
/// Usa banco e ajustes próprios; não lê nem altera os dados reais, não escaneia pastas e não registra o atalho global.
enum DemoMode {
    static let isOn = CommandLine.arguments.contains("--demo")

    /// Tela inicial pedida por `--screen`.
    static let screen: String? = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--screen"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }()

    private static let suiteName = "app.rastro.demo"

    /// Ajustes da demonstração, zerados a cada abertura.
    static let defaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }()

    static var databaseURL: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rastro-demo.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
        return url
    }
}
