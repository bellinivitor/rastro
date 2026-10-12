import SwiftUI

/// Ação de deploy do item selecionado na timeline, exposta ao menu do app.
struct DeployToggle {
    let title: String
    let perform: () -> Void
}

private struct DeployToggleKey: FocusedValueKey {
    typealias Value = DeployToggle
}

extension FocusedValues {
    var deployToggle: DeployToggle? {
        get { self[DeployToggleKey.self] }
        set { self[DeployToggleKey.self] = newValue }
    }
}

/// Menu "Deploy" com ⌘D: marca ou desmarca o commit/PR selecionado.
struct DeployCommands: Commands {
    @FocusedValue(\.deployToggle) private var toggle

    var body: some Commands {
        CommandMenu("Deploy") {
            Button(toggle?.title ?? "Lembrar de fazer deploy") { toggle?.perform() }
                .keyboardShortcut("d")
                .disabled(toggle == nil)
        }
    }
}
