import DevTimelineCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.rootPathKey) private var storedFolders = ""
    @AppStorage(AppSettings.authorEmailsKey) private var authorEmails = ""
    @AppStorage(AppSettings.gitHubEnabledKey) private var gitHubEnabled = true

    private var folders: [String] {
        get { AppSettings.split(storedFolders) }
        nonmutating set { storedFolders = newValue.joined(separator: "\n") }
    }

    var body: some View {
        Form {
            Section {
                if folders.isEmpty {
                    Text("Nenhuma pasta ainda.").foregroundStyle(.secondary)
                }
                ForEach(folders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(folder)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder)
                        Spacer()
                        Button {
                            folders.removeAll { $0 == folder }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Tirar esta pasta")
                        .accessibilityLabel("Tirar \(folder)")
                    }
                }
                Button("Adicionar pasta…", action: chooseFolders)
            } header: {
                Text("Pastas de repositórios")
            } footer: {
                Text("O app procura repositórios git dentro de cada pasta, até 4 níveis abaixo. Escaneia ao abrir e a cada 30 minutos.")
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Emails do autor", text: $authorEmails, prompt: Text("voce@exemplo.com, outro@empresa.com"))
            } header: {
                Text("Autor")
            } footer: {
                Text("Só commits desses emails entram na timeline. Separe vários por vírgula.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Buscar meus PRs no GitHub", isOn: $gitHubEnabled)
                    .disabled(GitHubCLI.executable == nil)
            } header: {
                Text("GitHub")
            } footer: {
                Text(GitHubCLI.executable == nil
                    ? "Instale o GitHub CLI (brew install gh) e rode gh auth login para ativar."
                    : "Usa o gh já logado no terminal; o app não guarda token. MRs do GitLab vêm dos merges locais e não precisam disso.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Adicionar"
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.map(\.path).filter { !folders.contains($0) }
        folders += added
        // Pasta nova: escaneia já, sem esperar os 30 minutos.
        if !added.isEmpty { Task { await AppStore.shared.scan() } }
    }
}
