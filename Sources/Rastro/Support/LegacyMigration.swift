import Foundation

/// O app se chamava "Dev Timeline". Na primeira abertura como Rastro, traz os dados e os ajustes do nome antigo.
enum LegacyMigration {
    static let oldFolder = "DevTimeline"
    static let oldDefaultsDomain = "app.devtimeline.mac"
    private static let doneKey = "rastro.legacyMigrated"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        // Banco: ~/Library/Application Support/DevTimeline → Rastro (só se a nova pasta ainda não existe).
        let fm = FileManager.default
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let old = support.appendingPathComponent(oldFolder, isDirectory: true)
            let new = support.appendingPathComponent("Rastro", isDirectory: true)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
                try? fm.moveItem(at: old, to: new)
            }
        }

        // Ajustes (pastas, emails, rascunho do standup…): copia o que ainda não foi definido no Rastro.
        if let old = defaults.persistentDomain(forName: oldDefaultsDomain) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
