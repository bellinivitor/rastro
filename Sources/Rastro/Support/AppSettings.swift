import Foundation

/// Chaves de UserDefaults compartilhadas entre @AppStorage e o código fora das views.
enum AppSettings {
    /// Os ajustes reais, ou os da demonstração (`--demo`), que ficam separados.
    static let defaults: UserDefaults = DemoMode.isOn ? DemoMode.defaults : .standard

    /// Pastas raiz, uma por linha. A chave é a mesma de quando só existia uma pasta,
    /// então a configuração antiga continua valendo como lista de um item.
    static let rootPathKey = "rootPath"
    static let authorEmailsKey = "authorEmails"
    static let gitHubEnabledKey = "gitHubEnabled"
    static let gitHubLastSyncKey = "gitHubLastSync"

    static var rootPaths: [String] {
        get { split(defaults.string(forKey: rootPathKey) ?? "") }
        set { defaults.set(newValue.joined(separator: "\n"), forKey: rootPathKey) }
    }

    static func split(_ stored: String) -> [String] {
        stored.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    /// Emails separados por vírgula.
    static var authorEmailList: [String] {
        (defaults.string(forKey: authorEmailsKey) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Buscar PRs pelo `gh`. Ligado por padrão.
    static var gitHubEnabled: Bool {
        defaults.object(forKey: gitHubEnabledKey) as? Bool ?? true
    }

    static var gitHubLastSync: Date? {
        get { defaults.object(forKey: gitHubLastSyncKey) as? Date }
        set { defaults.set(newValue, forKey: gitHubLastSyncKey) }
    }
}
