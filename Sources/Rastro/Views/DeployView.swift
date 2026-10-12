import RastroCore
import SwiftUI

/// Lista de "precisa ir para produção", por projeto.
struct DeployView: View {
    @Environment(AppStore.self) private var store

    private var pendingByProject: [(project: Project, tasks: [DeployTask])] {
        var order: [Int64] = []
        var tasks: [Int64: [DeployTask]] = [:]
        for task in store.pendingDeploys {
            if tasks[task.projectID] == nil { order.append(task.projectID) }
            tasks[task.projectID, default: []].append(task)
        }
        return order.compactMap { id in store.projectsByID[id].map { ($0, tasks[id, default: []]) } }
    }

    private var recentlyDone: [DeployTask] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        return store.deployTasks.filter { ($0.doneAt ?? .distantPast) >= weekAgo }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                AddDeployTaskBar()

                if pendingByProject.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nada esperando deploy.").font(.title3.weight(.semibold))
                        Text("Escreva uma tarefa acima, ou clique na caixinha de um commit ou PR da timeline.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(pendingByProject, id: \.project.id) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Circle().fill(Palette.project(group.project.colorHex)).frame(width: 9, height: 9)
                            Text(group.project.name).font(.headline)
                        }
                        ForEach(group.tasks) { task in
                            DeployTaskRow(task: task)
                        }
                    }
                }

                if !recentlyDone.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Feitos nos últimos 7 dias").font(.headline).foregroundStyle(.secondary)
                        ForEach(recentlyDone) { task in
                            DeployTaskRow(task: task, showsProject: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Deploy pendente")
    }
}

private struct DeployTaskRow: View {
    let task: DeployTask
    var showsProject = false

    @Environment(AppStore.self) private var store
    @State private var isHovering = false
    @State private var showsMembers = false
    @State private var renaming: Epic?

    private var epic: Epic? {
        guard task.kind == .epic, let id = task.ref.flatMap(Int64.init) else { return nil }
        return store.epics.first { $0.id == id }
    }

    private var members: [Event] { epic.map(store.events(in:)) ?? [] }

    private var memberSummary: String {
        let commits = members.filter { $0.kind == .commit }.count
        let prs = members.count - commits
        let parts = [
            commits > 0 ? (commits == 1 ? "1 commit" : "\(commits) commits") : nil,
            prs > 0 ? (prs == 1 ? "1 PR" : "\(prs) PRs") : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "vazia" : parts.joined(separator: " e ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row
            if showsMembers, epic != nil {
                memberList
                    .padding(.leading, 26)
                    .transition(.opacity)
            }
        }
        .sheet(item: $renaming) { epic in
            EpicNameView(epic: epic)
        }
    }

    /// Commits da epic, cada um com um × para tirar.
    private var memberList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(members) { event in
                HStack(spacing: 8) {
                    Circle().fill(Color.secondary).frame(width: 4, height: 4)
                    Text(event.kind == .pullRequest
                         ? "\(event.ref ?? "PR") \(CommitMessage.parse(event.title).text)"
                         : CommitMessage.parse(event.title).headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(event.date, format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(.tertiary)
                    if task.isPending {
                        Button {
                            store.removeFromEpic([event])
                        } label: {
                            Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Tirar da epic")
                        .accessibilityLabel("Tirar \(event.title) da epic")
                    }
                }
                .font(.callout)
            }
            if members.isEmpty {
                Text("Nenhum commit. Adicione pela timeline: selecione com ⌘-clique ou use o clique direito.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                withAnimation(.snappy) { store.setDeployed(task, done: task.isPending) }
            } label: {
                Image(systemName: task.isPending ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(task.isPending ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(task.isPending ? "Marcar como feito" : "Reabrir")
            .accessibilityLabel(task.isPending ? "Marcar como feito" : "Reabrir")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if task.kind == .epic {
                        Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
                    }
                    Text(task.title)
                        .fontWeight(task.kind == .epic ? .semibold : .regular)
                        .foregroundStyle(task.isPending ? .primary : .secondary)
                        .strikethrough(!task.isPending, color: .secondary)
                }
                HStack(spacing: 10) {
                    if showsProject, let name = store.projectsByID[task.projectID]?.name { Text(name) }
                    if epic != nil {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { showsMembers.toggle() }
                        } label: {
                            HStack(spacing: 3) {
                                Text("Epic com \(memberSummary)")
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .rotationEffect(.degrees(showsMembers ? 180 : 0))
                            }
                        }
                        .buttonStyle(.plain)
                        .help(showsMembers ? "Esconder os commits" : "Ver os commits da epic")
                    }
                    // Só o PR ganha referência: é o número que você procura no GitHub/GitLab.
                    if task.kind == .pullRequest, let ref = task.ref { Text(ref) }
                    Text((task.doneAt ?? task.createdAt).formatted(.relative(presentation: .named)))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                // Apagar a epic tira o agrupamento; os commits continuam na timeline.
                withAnimation(.snappy) {
                    if let epic { store.deleteEpic(epic) } else { store.deleteDeployTask(task) }
                }
            } label: {
                Image(systemName: "trash")
                    // Sempre visível (é assim que se descobre que dá para apagar); mais forte no hover.
                    .foregroundStyle(isHovering ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)
            .help("Apagar")
            .accessibilityLabel("Apagar \(task.title)")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(isHovering ? Color.primary.opacity(0.05) : .clear)
        )
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(task.isPending ? "Marcar como feito" : "Reabrir") { store.setDeployed(task, done: task.isPending) }
            if let epic {
                Button("Renomear epic…") { renaming = epic }
                Button("Apagar epic", role: .destructive) { store.deleteEpic(epic) }
            } else {
                Button("Apagar", role: .destructive) { store.deleteDeployTask(task) }
            }
        }
    }
}

/// Uma linha: projeto e o que precisa ir para produção.
private struct AddDeployTaskBar: View {
    @Environment(AppStore.self) private var store

    @State private var projectID: Int64?
    @State private var text = ""

    private var projects: [Project] {
        store.projects
            .filter { !$0.isHidden && store.eventCounts[$0.id, default: 0] > 0 }
            .sorted { ($0.lastCommitAt ?? .distantPast) > ($1.lastCommitAt ?? .distantPast) }
    }

    private var canAdd: Bool {
        projectID != nil && !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            Picker("Projeto", selection: $projectID) {
                ForEach(projects) { Text($0.name).tag(Int64?.some($0.id)) }
            }
            .labelsHidden()
            .frame(maxWidth: 200)

            TextField("O que precisa ir para produção?", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)

            Button("Adicionar", action: add)
                .disabled(!canAdd)
        }
        .onAppear { if projectID == nil { projectID = projects.first?.id } }
    }

    private func add() {
        guard canAdd, let projectID else { return }
        store.addDeployTask(projectID: projectID, kind: .text, ref: nil, title: text.trimmingCharacters(in: .whitespaces))
        text = ""
    }
}
