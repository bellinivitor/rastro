import RastroCore
import SwiftUI

/// Pedido de criação de epic a partir de alguns eventos (identificável para `.sheet(item:)`).
struct EpicDraft: Identifiable {
    let id = UUID()
    let events: [Event]
}

/// Criar uma epic com os eventos escolhidos, ou renomear uma existente.
struct EpicNameView: View {
    var draft: EpicDraft?
    var epic: Epic?
    var onDone: () -> Void = {}

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var events: [Event] { draft?.events.filter(AppStore.canJoinEpic) ?? [] }

    private var summary: String {
        let project = events.first.flatMap { store.project(for: $0)?.name } ?? ""
        let count = events.count == 1 ? "1 item" : "\(events.count) itens"
        return "\(count) de \(project) vão subir juntos."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(epic == nil ? "Nova epic" : "Renomear epic").font(.headline)
            if epic == nil {
                Text(summary).foregroundStyle(.secondary)
            }
            TextField("Nome da epic", text: $name, prompt: Text("Ex: Nova tela de login"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(epic == nil ? "Criar epic" : "Renomear", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { name = epic?.name ?? "" }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let epic {
            store.renameEpic(epic, to: name)
        } else {
            store.createEpic(named: name, with: events)
        }
        onDone()
        dismiss()
    }
}

/// Barra que aparece com 2 ou mais itens selecionados na timeline.
struct EpicSelectionBar: View {
    let selected: [Event]
    let onCreateEpic: () -> Void
    let onClear: () -> Void

    @Environment(AppStore.self) private var store

    private var eligible: [Event] { selected.filter(AppStore.canJoinEpic) }
    private var projectIDs: Set<Int64> { Set(eligible.compactMap(\.projectID)) }

    var body: some View {
        HStack(spacing: 12) {
            if projectIDs.count > 1 {
                Label("Itens de \(projectIDs.count) projetos. Uma epic é de um projeto só.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            } else if eligible.isEmpty {
                Text("Só commits e PRs entram numa epic.").foregroundStyle(.secondary)
            } else {
                let project = projectIDs.first.flatMap { store.projectsByID[$0]?.name } ?? ""
                Text("\(eligible.count) \(eligible.count == 1 ? "item" : "itens") de \(project)")
                    .fontWeight(.medium)
            }

            Spacer()

            if projectIDs.count == 1, let projectID = projectIDs.first {
                let open = store.openEpics(in: projectID)
                if !open.isEmpty {
                    Menu("Adicionar à epic") {
                        ForEach(open) { epic in
                            Button(epic.name) {
                                store.add(eligible, to: epic)
                                onClear()
                            }
                        }
                    }
                    .fixedSize()
                }
                Button("Criar epic…", action: onCreateEpic)
                    .buttonStyle(.borderedProminent)
            }

            Button(action: onClear) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Limpar seleção (Esc)")
            .accessibilityLabel("Limpar seleção")
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
