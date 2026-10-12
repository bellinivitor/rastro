import DevTimelineCore
import Foundation
import Observation

/// Estado do app em memória, recarregado do banco depois de cada escrita.
@MainActor
@Observable
final class AppStore {
    /// Uma instância para a janela, os Ajustes e a nota rápida global.
    static let shared = AppStore()

    private let database: Database

    private(set) var projects: [Project] = []
    private(set) var groups: [ProjectGroup] = []
    /// Eventos visíveis: sem os de projetos ocultos.
    private(set) var events: [Event] = []
    private(set) var projectsByID: [Int64: Project] = [:]
    private(set) var eventCounts: [Int64: Int] = [:]
    private(set) var deployTasks: [DeployTask] = []
    private(set) var epics: [Epic] = []
    /// uid do evento → id da epic.
    private(set) var epicMembers: [String: Int64] = [:]

    private(set) var isScanning = false
    private(set) var status: String?

    init() {
        do {
            database = try Database(path: Database.defaultURL().path)
        } catch {
            // Sem banco em disco o app ainda abre, mas nada persiste.
            database = try! Database(path: ":memory:")
            status = "Erro ao abrir o banco: \(error)"
        }
        reload()
    }

    func reload() {
        do {
            projects = try database.projects()
            groups = try database.groups()
            let hidden = Set(projects.filter(\.isHidden).map(\.id))
            events = try database.events().filter { $0.projectID.map { !hidden.contains($0) } ?? true }
            deployTasks = try database.deployTasks()
            epics = try database.epics()
            epicMembers = try database.epicMembers()
        } catch {
            status = "Erro ao ler o banco: \(error)"
        }
        projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        eventCounts = events.reduce(into: [:]) { counts, event in
            if let id = event.projectID { counts[id, default: 0] += 1 }
        }
    }

    /// Aviso que não pode ser apagado pela próxima mensagem de escaneamento.
    var shortcutWarning: String?

    func project(for event: Event) -> Project? {
        event.projectID.flatMap { projectsByID[$0] }
    }

    /// Escaneia ao abrir e depois a cada 30 minutos, enquanto o app estiver aberto.
    func startAutoScan(every interval: Duration = .seconds(30 * 60)) {
        guard autoScanTask == nil else { return }
        autoScanTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(for: interval)
            }
        }
    }

    @ObservationIgnored private var autoScanTask: Task<Void, Never>?
    private(set) var lastScanAt: Date?

    func scan() async {
        guard !isScanning else { return }
        let roots = AppSettings.rootPaths
        guard !roots.isEmpty else {
            status = "Adicione uma pasta de repositórios nos Ajustes"
            return
        }

        isScanning = true
        defer { isScanning = false }
        status = "Escaneando…"

        let emails = AppSettings.authorEmailList
        let since = Dictionary(
            projects.compactMap { p in p.lastCommitAt.map { (p.path, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let repos = await Task.detached(priority: .userInitiated) {
            GitScanner.scan(roots: roots.map { URL(fileURLWithPath: $0) }, authorEmails: emails, since: since)
        }.value

        let importer = Importer(database: database, palette: Palette.colors)
        do {
            let inserted = try importer.importRepos(repos)
            lastScanAt = .now
            let time = Date.now.formatted(date: .omitted, time: .shortened)
            status = inserted == 0
                ? "Atualizado às \(time). Nada novo em \(repos.count) repositórios."
                : "Atualizado às \(time). \(inserted) novos eventos em \(repos.count) repositórios."
        } catch {
            status = "Erro ao importar: \(error)"
            reload()
            return
        }
        reload()

        await syncGitHub(importer)
        reload()
    }

    /// PRs do GitHub pelo `gh`, quando ele existe e a opção está ligada. Falha aqui não desfaz o escaneamento local.
    private func syncGitHub(_ importer: Importer) async {
        guard AppSettings.gitHubEnabled, GitHubCLI.executable != nil else { return }
        // Primeira vez: últimos 6 meses. Depois: desde a última busca, com margem de 2 dias.
        let since = AppSettings.gitHubLastSync?.addingTimeInterval(-2 * 86_400)
            ?? Calendar.current.date(byAdding: .month, value: -6, to: .now)!
        let result = await Task.detached(priority: .userInitiated) {
            Result { try GitHubCLI.fetch(since: since) }
        }.value

        do {
            let inserted = try importer.importPullRequests(result.get())
            AppSettings.gitHubLastSync = .now
            if inserted > 0 { status = (status ?? "") + ", \(inserted) do GitHub" }
        } catch {
            status = "Não foi possível buscar os PRs do GitHub: \(error). Rode gh auth status no terminal."
        }
    }

    func updateNote(_ note: Event, title: String, detail: String?, date: Date, projectID: Int64?) {
        write("salvar a nota") {
            try database.updateNote(id: note.id, title: title, detail: detail, date: date, projectID: projectID)
        }
    }

    func addNote(title: String, detail: String?, date: Date, projectID: Int64?) {
        do {
            try database.insertEvent(uid: "note:\(UUID().uuidString)", kind: .note, date: date, title: title, detail: detail, projectID: projectID)
        } catch {
            status = "Erro ao salvar nota: \(error)"
        }
        reload()
    }

    func delete(_ event: Event) {
        do {
            try database.deleteEvent(id: event.id)
        } catch {
            status = "Erro ao apagar: \(error)"
        }
        reload()
    }

    /// Corpo da mensagem do commit, lido do git na hora (não fica no banco).
    func commitBody(for event: Event) async -> String? {
        guard let hash = event.commitHash, let path = project(for: event)?.path else { return nil }
        return await Task.detached(priority: .userInitiated) {
            GitScanner.commitBody(repoPath: path, hash: hash)
        }.value
    }

    // MARK: Deploy

    var pendingDeploys: [DeployTask] { deployTasks.filter(\.isPending) }

    func pendingDeploy(for event: Event) -> DeployTask? {
        deployTasks.first { $0.isPending && $0.eventUID == event.uid }
    }

    /// "Lembrar de fazer deploy" a partir de um commit ou PR da timeline.
    func remindDeploy(_ event: Event) {
        guard let projectID = event.projectID, pendingDeploy(for: event) == nil, let draft = DeployTask.draft(from: event) else { return }
        write("criar o lembrete") {
            try database.insertDeployTask(projectID: projectID, kind: draft.kind, ref: draft.ref, title: draft.title, eventUID: event.uid)
        }
    }

    func addDeployTask(projectID: Int64, kind: DeployTask.Kind, ref: String?, title: String) {
        write("criar o lembrete") {
            try database.insertDeployTask(projectID: projectID, kind: kind, ref: ref, title: title)
        }
    }

    func setDeployed(_ task: DeployTask, done: Bool) {
        write(done ? "marcar o deploy" : "reabrir o deploy") {
            try database.setDeployed(task, at: done ? .now : nil)
        }
    }

    func deleteDeployTask(_ task: DeployTask) {
        write("apagar o lembrete") { try database.deleteDeployTask(id: task.id) }
    }

    private func write(_ action: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            status = "Não foi possível \(action): \(error)"
        }
        reload()
    }

    // MARK: Configuração de projetos e grupos

    /// Projetos com algum evento seu, fora os ocultos.
    var sidebarProjects: [Project] {
        projects.filter { !$0.isHidden && eventCounts[$0.id, default: 0] > 0 }
    }

    var hiddenProjects: [Project] { projects.filter(\.isHidden) }

    func updateProject(_ project: Project) {
        write("salvar o projeto") { try database.updateSettings(project) }
    }

    func toggleFavorite(_ project: Project) {
        var changed = project
        changed.isFavorite.toggle()
        updateProject(changed)
    }

    func setHidden(_ hidden: Bool, _ project: Project) {
        var changed = project
        changed.isHidden = hidden
        updateProject(changed)
    }

    func move(_ project: Project, to groupID: Int64?) {
        var changed = project
        changed.groupID = groupID
        updateProject(changed)
    }

    /// Cria o grupo (ou reaproveita um com o mesmo nome) e, se pedido, já move o projeto para ele.
    @discardableResult
    func createGroup(named name: String, moving project: Project? = nil) -> ProjectGroup? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var created: ProjectGroup?
        write("criar o grupo") {
            created = try database.group(named: name)
            if var project, let created {
                project.groupID = created.id
                try database.updateSettings(project)
            }
        }
        return created
    }

    func renameGroup(_ group: ProjectGroup, to name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        write("renomear o grupo") { try database.renameGroup(id: group.id, to: name) }
    }

    func deleteGroup(_ group: ProjectGroup) {
        write("apagar o grupo") { try database.deleteGroup(id: group.id) }
    }

    // MARK: Epics

    func epic(for event: Event) -> Epic? {
        epicMembers[event.uid].flatMap { id in epics.first { $0.id == id } }
    }

    func deployTask(for epic: Epic) -> DeployTask? {
        deployTasks.first { $0.kind == .epic && $0.ref == String(epic.id) }
    }

    /// Epics que ainda não subiram, de um projeto: as que aceitam novos commits.
    func openEpics(in projectID: Int64) -> [Epic] {
        epics.filter { $0.projectID == projectID && deployTask(for: $0)?.isPending != false }
    }

    func events(in epic: Epic) -> [Event] {
        events.filter { epicMembers[$0.uid] == epic.id }.sorted { $0.date < $1.date }
    }

    /// Commits e PRs com projeto: o que pode entrar numa epic.
    static func canJoinEpic(_ event: Event) -> Bool {
        event.projectID != nil && (event.kind == .commit || event.kind == .pullRequest)
    }

    func createEpic(named name: String, with events: [Event]) {
        let eligible = events.filter(Self.canJoinEpic)
        guard let projectID = eligible.first?.projectID, eligible.allSatisfy({ $0.projectID == projectID }),
              !name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }
        write("criar a epic") {
            try database.createEpic(projectID: projectID, name: name, eventUIDs: eligible.map(\.uid))
        }
    }

    func add(_ events: [Event], to epic: Epic) {
        let eligible = events.filter { Self.canJoinEpic($0) && $0.projectID == epic.projectID }
        write("adicionar à epic") { try database.addToEpic(epic.id, eventUIDs: eligible.map(\.uid)) }
    }

    func removeFromEpic(_ events: [Event]) {
        write("tirar da epic") { try database.removeFromEpic(eventUIDs: events.map(\.uid)) }
    }

    func renameEpic(_ epic: Epic, to name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        write("renomear a epic") { try database.renameEpic(id: epic.id, to: name) }
    }

    func deleteEpic(_ epic: Epic) {
        write("apagar a epic") { try database.deleteEpic(id: epic.id) }
    }
}
