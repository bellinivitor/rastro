import RastroCore
import SwiftUI

enum SidebarItem: Hashable {
    case timeline
    case stats
    case deploys
    case group(Int64)
    case project(Int64)
    /// Mesmo projeto, mas a linha da seção Favoritos (evita destacar duas linhas ao mesmo tempo).
    case favorite(Int64)
}

/// Folha aberta a partir da barra lateral.
enum SidebarSheet: Identifiable {
    case settings(Project)
    case newGroup(moving: Project?)
    case renameGroup(ProjectGroup)

    var id: String {
        switch self {
        case .settings(let project): "settings-\(project.id)"
        case .newGroup(let project): "new-group-\(project?.id ?? 0)"
        case .renameGroup(let group): "rename-\(group.id)"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(AppStore.self) private var store

    @State private var sheet: SidebarSheet?
    @State private var collapsedGroups: Set<Int64> = []
    @State private var showsHidden = false

    private var favorites: [Project] { store.sidebarProjects.filter(\.isFavorite) }

    private func projects(in groupID: Int64?) -> [Project] {
        store.sidebarProjects
            .filter { $0.groupID == groupID }
            .sorted { ($0.isFavorite ? 0 : 1, $0.name.lowercased()) < ($1.isFavorite ? 0 : 1, $1.name.lowercased()) }
    }

    var body: some View {
        List(selection: $selection) {
            Section("Visão") {
                Label("Timeline", systemImage: "clock").tag(SidebarItem.timeline)
                Label("Estatísticas", systemImage: "chart.bar").tag(SidebarItem.stats)
                Label("Deploy pendente", systemImage: "shippingbox")
                    .badge(store.pendingDeploys.count)
                    .tag(SidebarItem.deploys)
            }

            if !favorites.isEmpty {
                Section("Favoritos") {
                    ForEach(favorites) { project in
                        ProjectRow(project: project, showsStar: false, sheet: $sheet)
                            .tag(SidebarItem.favorite(project.id))
                    }
                }
            }

            Section("Projetos") {
                ForEach(store.groups) { group in
                    let members = projects(in: group.id)
                    if !members.isEmpty {
                        DisclosureGroup(isExpanded: expansion(for: group.id)) {
                            ForEach(members) { project in
                                ProjectRow(project: project, showsStar: true, sheet: $sheet)
                                    .tag(SidebarItem.project(project.id))
                            }
                        } label: {
                            GroupRow(group: group, members: members, sheet: $sheet)
                                .tag(SidebarItem.group(group.id))
                        }
                    }
                }

                ForEach(projects(in: nil)) { project in
                    ProjectRow(project: project, showsStar: true, sheet: $sheet)
                        .tag(SidebarItem.project(project.id))
                }

                if !store.hiddenProjects.isEmpty {
                    DisclosureGroup(isExpanded: $showsHidden) {
                        ForEach(store.hiddenProjects) { project in
                            HiddenProjectRow(project: project, sheet: $sheet)
                        }
                    } label: {
                        Label("Ocultos (\(store.hiddenProjects.count))", systemImage: "eye.slash")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .settings(let project):
                ProjectSettingsView(project: project)
            case .newGroup(let project):
                GroupNameView(group: nil, moving: project)
            case .renameGroup(let group):
                GroupNameView(group: group, moving: nil)
            }
        }
    }

    private func expansion(for id: Int64) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(id) },
            set: { expanded in
                if expanded { collapsedGroups.remove(id) } else { collapsedGroups.insert(id) }
            }
        )
    }
}

private struct GroupRow: View {
    let group: ProjectGroup
    let members: [Project]
    @Binding var sheet: SidebarSheet?
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack {
            Label(group.name, systemImage: "folder")
            Spacer()
            Text("\(members.reduce(0) { $0 + store.eventCounts[$1.id, default: 0] })")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contextMenu {
            Button("Renomear grupo…") { sheet = .renameGroup(group) }
            Button("Apagar grupo", role: .destructive) { store.deleteGroup(group) }
        }
        .help("Clique para ver a timeline de todos os projetos de \(group.name)")
    }
}

private struct ProjectRow: View {
    let project: Project
    let showsStar: Bool
    @Binding var sheet: SidebarSheet?
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Palette.project(project.colorHex)).frame(width: 8, height: 8)
            Text(project.name)
                .fontWeight(project.isFavorite ? .semibold : .regular)
                .lineLimit(1)
            if showsStar && project.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorito")
            }
            Spacer()
            Text("\(store.eventCounts[project.id, default: 0])")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contextMenu { ProjectMenu(project: project, sheet: $sheet) }
    }
}

private struct HiddenProjectRow: View {
    let project: Project
    @Binding var sheet: SidebarSheet?
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Palette.project(project.colorHex).opacity(0.5)).frame(width: 8, height: 8)
            Text(project.name).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Mostrar") { store.setHidden(false, project) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .contextMenu {
            Button("Mostrar de novo") { store.setHidden(false, project) }
            Button("Configurar…") { sheet = .settings(project) }
        }
    }
}

/// Ações do clique direito num projeto.
private struct ProjectMenu: View {
    let project: Project
    @Binding var sheet: SidebarSheet?
    @Environment(AppStore.self) private var store

    var body: some View {
        Button(project.isFavorite ? "Remover dos favoritos" : "Favoritar") { store.toggleFavorite(project) }

        Menu("Mover para grupo") {
            ForEach(store.groups) { group in
                Button {
                    store.move(project, to: group.id)
                } label: {
                    if project.groupID == group.id { Label(group.name, systemImage: "checkmark") } else { Text(group.name) }
                }
            }
            if !store.groups.isEmpty { Divider() }
            Button("Novo grupo…") { sheet = .newGroup(moving: project) }
            if project.groupID != nil {
                Button("Tirar do grupo") { store.move(project, to: nil) }
            }
        }

        Button("Configurar…") { sheet = .settings(project) }
        Divider()
        Button("Esconder") { store.setHidden(true, project) }
    }
}
