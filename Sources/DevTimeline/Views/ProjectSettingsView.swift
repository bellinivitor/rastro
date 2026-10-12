import DevTimelineCore
import SwiftUI

/// Nome, cor, favorito, grupo e visibilidade de um projeto.
struct ProjectSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var project: Project
    @State private var groupChoice: GroupChoice
    @State private var newGroupName = ""

    enum GroupChoice: Hashable {
        case none
        case existing(Int64)
        case new
    }

    init(project: Project) {
        _project = State(initialValue: project)
        _groupChoice = State(initialValue: project.groupID.map { .existing($0) } ?? .none)
    }

    private var folderName: String { URL(fileURLWithPath: project.path).lastPathComponent }

    private var canSave: Bool {
        !project.name.trimmingCharacters(in: .whitespaces).isEmpty
            && (groupChoice != .new || !newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Nome", text: $project.name, prompt: Text(folderName))
                    LabeledContent("Cor") {
                        HStack(spacing: 8) {
                            ForEach(Palette.categorical, id: \.light) { color in
                                ColorSwatch(hex: color.light, isSelected: project.colorHex.caseInsensitiveCompare(color.light) == .orderedSame) {
                                    project.colorHex = color.light
                                }
                            }
                        }
                    }
                    Toggle("Favorito", isOn: $project.isFavorite)
                } footer: {
                    Text(project.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Section {
                    Picker("Grupo", selection: $groupChoice) {
                        Text("Nenhum").tag(GroupChoice.none)
                        if !store.groups.isEmpty { Divider() }
                        ForEach(store.groups) { Text($0.name).tag(GroupChoice.existing($0.id)) }
                        Divider()
                        Text("Novo grupo…").tag(GroupChoice.new)
                    }
                    if groupChoice == .new {
                        TextField("Nome do grupo", text: $newGroupName, prompt: Text("Ex: nome do cliente"))
                    }
                } footer: {
                    Text("Use um grupo por cliente. Clicar no grupo na barra lateral mostra a timeline de todos os projetos dele.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Esconder este projeto", isOn: $project.isHidden)
                } footer: {
                    Text("Some da barra lateral, da timeline, do standup e das estatísticas. Dá para mostrar de novo em Ocultos.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 480)
    }

    private func save() {
        var changed = project
        changed.name = changed.name.trimmingCharacters(in: .whitespaces)
        switch groupChoice {
        case .none: changed.groupID = nil
        case .existing(let id): changed.groupID = id
        case .new: changed.groupID = store.createGroup(named: newGroupName)?.id
        }
        store.updateProject(changed)
        dismiss()
    }
}

private struct ColorSwatch: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Palette.project(hex))
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cor \(hex)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Criar um grupo (opcionalmente já movendo um projeto) ou renomear um existente.
struct GroupNameView: View {
    let group: ProjectGroup?
    let moving: Project?

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(group == nil ? "Novo grupo" : "Renomear grupo").font(.headline)
            if let moving {
                Text("\(moving.name) vai para o grupo novo.")
                    .foregroundStyle(.secondary)
            }
            TextField("Nome do grupo", text: $name, prompt: Text("Ex: nome do cliente"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(group == nil ? "Criar" : "Renomear", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { name = group?.name ?? "" }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let group {
            store.renameGroup(group, to: name)
        } else {
            store.createGroup(named: name, moving: moving)
        }
        dismiss()
    }
}
