import Foundation

/// Persistência do app. Use sempre da mesma thread (o app usa só na main).
public final class Database {
    private let db: SQLiteConnection

    /// `~/Library/Application Support/DevTimeline/timeline.sqlite`
    public static func defaultURL() throws -> URL {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("DevTimeline", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("timeline.sqlite")
    }

    /// Use `":memory:"` nos testes.
    public init(path: String) throws {
        db = try SQLiteConnection(path: path)
        try migrate()
    }

    // MARK: Migrações

    private static let migrations = [
        """
        CREATE TABLE projects (
            id INTEGER PRIMARY KEY,
            path TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            last_scanned_at REAL,
            last_commit_at REAL
        );
        CREATE TABLE events (
            id INTEGER PRIMARY KEY,
            uid TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            date REAL NOT NULL,
            title TEXT NOT NULL,
            detail TEXT,
            author TEXT,
            project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE
        );
        CREATE INDEX events_date ON events(date DESC);
        CREATE INDEX events_project ON events(project_id);
        """,
        // Troca a paleta inicial pela paleta validada para daltonismo (mesma posição, módulo 8).
        """
        UPDATE projects SET color = CASE upper(color)
            WHEN '#4F7CFF' THEN '#2a78d6' WHEN '#F2994A' THEN '#eb6834'
            WHEN '#27AE60' THEN '#1baf7a' WHEN '#EB5757' THEN '#eda100'
            WHEN '#9B51E0' THEN '#e87ba4' WHEN '#2D9CDB' THEN '#008300'
            WHEN '#F2C94C' THEN '#4a3aa7' WHEN '#219653' THEN '#e34948'
            WHEN '#BB6BD9' THEN '#2a78d6' WHEN '#56CCF2' THEN '#eb6834'
            ELSE color END;
        """,
        // Pull/merge requests e remote de cada projeto.
        """
        ALTER TABLE projects ADD COLUMN remote TEXT;
        ALTER TABLE events ADD COLUMN ref TEXT;
        ALTER TABLE events ADD COLUMN state TEXT;
        ALTER TABLE events ADD COLUMN url TEXT;
        -- Força um escaneamento completo para ler os merges antigos (commits repetidos são ignorados).
        UPDATE projects SET last_commit_at = NULL;
        """,
        // Pendências de deploy por projeto. (deploy_branch ficou sem uso.)
        """
        ALTER TABLE projects ADD COLUMN deploy_branch TEXT;
        CREATE TABLE deploy_tasks (
            id INTEGER PRIMARY KEY,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            kind TEXT NOT NULL,
            ref TEXT,
            title TEXT NOT NULL,
            event_uid TEXT,
            created_at REAL NOT NULL,
            done_at REAL
        );
        CREATE INDEX deploy_tasks_project ON deploy_tasks(project_id);
        """,
        // Configuração por projeto: favorito, oculto e grupo (cliente).
        """
        CREATE TABLE project_groups (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL UNIQUE COLLATE NOCASE
        );
        ALTER TABLE projects ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE projects ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE projects ADD COLUMN group_id INTEGER REFERENCES project_groups(id) ON DELETE SET NULL;
        """,
        // Epics: commits/PRs de um projeto que sobem juntos. Cada evento está em no máximo uma epic.
        """
        CREATE TABLE epics (
            id INTEGER PRIMARY KEY,
            project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE TABLE epic_events (
            event_uid TEXT PRIMARY KEY,
            epic_id INTEGER NOT NULL REFERENCES epics(id) ON DELETE CASCADE
        );
        CREATE INDEX epic_events_epic ON epic_events(epic_id);
        """,
    ]

    private func migrate() throws {
        let version = try db.query("PRAGMA user_version") { $0.int(0) }.first ?? 0
        for (index, sql) in Self.migrations.enumerated() where index >= version {
            try db.transaction {
                try db.execute(sql)
                try db.execute("PRAGMA user_version = \(index + 1)")
            }
        }
    }

    // MARK: Projetos

    private static let projectColumns = "id, path, name, color, last_scanned_at, last_commit_at, remote, favorite, hidden, group_id"

    private static func project(_ row: SQLiteConnection.Row) -> Project {
        Project(
            id: row.int64(0), path: row.string(1), name: row.string(2), colorHex: row.string(3),
            lastScannedAt: row.optionalDate(4), lastCommitAt: row.optionalDate(5), remote: row.optionalString(6),
            isFavorite: row.bool(7), isHidden: row.bool(8), groupID: row.optionalInt64(9)
        )
    }

    public func projects() throws -> [Project] {
        try db.query("SELECT \(Self.projectColumns) FROM projects ORDER BY name COLLATE NOCASE", row: Self.project)
    }

    public func insertProject(path: String, name: String, colorHex: String) throws -> Project {
        try db.run("INSERT INTO projects (path, name, color) VALUES (?, ?, ?)", [path, name, colorHex])
        return Project(id: db.lastInsertID, path: path, name: name, colorHex: colorHex)
    }

    public func updateScan(projectID: Int64, scannedAt: Date, lastCommitAt: Date?, remote: String?) throws {
        try db.run(
            "UPDATE projects SET last_scanned_at = ?, last_commit_at = ?, remote = coalesce(?, remote) WHERE id = ?",
            [scannedAt, lastCommitAt, remote, projectID]
        )
    }

    /// Grava o que o usuário configura: nome, cor, favorito, oculto e grupo.
    public func updateSettings(_ project: Project) throws {
        try db.run(
            "UPDATE projects SET name = ?, color = ?, favorite = ?, hidden = ?, group_id = ? WHERE id = ?",
            [project.name, project.colorHex, project.isFavorite, project.isHidden, project.groupID, project.id]
        )
    }

    // MARK: Grupos

    public func groups() throws -> [ProjectGroup] {
        try db.query("SELECT id, name FROM project_groups ORDER BY name COLLATE NOCASE") {
            ProjectGroup(id: $0.int64(0), name: $0.string(1))
        }
    }

    /// Cria o grupo, ou devolve o existente com o mesmo nome (sem diferenciar maiúsculas).
    public func group(named name: String) throws -> ProjectGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.run("INSERT OR IGNORE INTO project_groups (name) VALUES (?)", [trimmed])
        return try db.query("SELECT id, name FROM project_groups WHERE name = ?", [trimmed]) {
            ProjectGroup(id: $0.int64(0), name: $0.string(1))
        }.first!
    }

    public func renameGroup(id: Int64, to name: String) throws {
        try db.run("UPDATE project_groups SET name = ? WHERE id = ?", [name.trimmingCharacters(in: .whitespacesAndNewlines), id])
    }

    /// Os projetos do grupo ficam sem grupo; nada é apagado deles.
    public func deleteGroup(id: Int64) throws {
        try db.run("DELETE FROM project_groups WHERE id = ?", [id])
    }

    // MARK: Eventos

    private static let eventColumns = "id, uid, kind, date, title, detail, author, project_id, ref, state, url"

    private static func event(_ row: SQLiteConnection.Row) -> Event {
        Event(
            id: row.int64(0), uid: row.string(1), kind: EventKind(rawValue: row.string(2)) ?? .note,
            date: row.date(3), title: row.string(4), detail: row.optionalString(5),
            author: row.optionalString(6), projectID: row.optionalInt64(7),
            ref: row.optionalString(8), state: row.optionalString(9), url: row.optionalString(10)
        )
    }

    /// Todos os eventos, do mais recente para o mais antigo.
    public func events() throws -> [Event] {
        try db.query("SELECT \(Self.eventColumns) FROM events ORDER BY date DESC, id DESC", row: Self.event)
    }

    /// Insere se o `uid` ainda não existe. Retorna `true` se gravou.
    @discardableResult
    public func insertEvent(
        uid: String, kind: EventKind, date: Date, title: String, detail: String? = nil, author: String? = nil,
        projectID: Int64? = nil, ref: String? = nil, state: String? = nil, url: String? = nil
    ) throws -> Bool {
        try db.run(
            "INSERT OR IGNORE INTO events (uid, kind, date, title, detail, author, project_id, ref, state, url) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [uid, kind.rawValue, date, title, detail, author, projectID, ref, state, url]
        )
        return db.changes > 0
    }

    /// Só notas são editáveis; commits e PRs vêm do git.
    public func updateNote(id: Int64, title: String, detail: String?, date: Date, projectID: Int64?) throws {
        try db.run(
            "UPDATE events SET title = ?, detail = ?, date = ?, project_id = ? WHERE id = ? AND kind = ?",
            [title, detail, date, projectID, id, EventKind.note.rawValue]
        )
    }

    public func deleteEvent(id: Int64) throws {
        try db.run("DELETE FROM events WHERE id = ?", [id])
    }

    // MARK: Deploy

    private static let deployColumns = "id, project_id, kind, ref, title, event_uid, created_at, done_at"

    private static func deployTask(_ row: SQLiteConnection.Row) -> DeployTask {
        DeployTask(
            id: row.int64(0), projectID: row.int64(1), kind: DeployTask.Kind(rawValue: row.string(2)) ?? .text,
            ref: row.optionalString(3), title: row.string(4), eventUID: row.optionalString(5),
            createdAt: row.date(6), doneAt: row.optionalDate(7)
        )
    }

    /// Pendentes primeiro (mais recentes no topo), depois as feitas.
    public func deployTasks() throws -> [DeployTask] {
        try db.query(
            "SELECT \(Self.deployColumns) FROM deploy_tasks ORDER BY done_at IS NOT NULL, coalesce(done_at, created_at) DESC, id DESC",
            row: Self.deployTask
        )
    }

    @discardableResult
    public func insertDeployTask(projectID: Int64, kind: DeployTask.Kind, ref: String?, title: String, eventUID: String? = nil, createdAt: Date = .now) throws -> DeployTask {
        try db.run(
            "INSERT INTO deploy_tasks (project_id, kind, ref, title, event_uid, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            [projectID, kind.rawValue, ref, title, eventUID, createdAt]
        )
        return DeployTask(id: db.lastInsertID, projectID: projectID, kind: kind, ref: ref, title: title, eventUID: eventUID, createdAt: createdAt)
    }

    /// Marca como feita (gera um evento `deploy` na timeline) ou reabre (remove o evento).
    /// Epic feita leva junto os lembretes soltos dos commits dela, que deixam de fazer sentido.
    public func setDeployed(_ task: DeployTask, at date: Date?) throws {
        try db.transaction {
            try db.run("UPDATE deploy_tasks SET done_at = ? WHERE id = ?", [date, task.id])
            if task.kind == .epic, date != nil, let epicID = task.ref.flatMap(Int64.init) {
                try db.run(
                    "DELETE FROM deploy_tasks WHERE done_at IS NULL AND event_uid IN (SELECT event_uid FROM epic_events WHERE epic_id = ?)",
                    [epicID]
                )
            }
            let uid = "deploy:\(task.id)"
            if let date {
                let title: String = switch task.kind {
                case .branch: "Branch \(task.ref ?? task.title)"
                case .epic: "Epic \(task.title)"
                default: task.title
                }
                try db.run(
                    "INSERT OR REPLACE INTO events (uid, kind, date, title, detail, project_id, ref) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    [uid, EventKind.deploy.rawValue, date, title, nil, task.projectID, task.kind == .pullRequest ? task.ref : nil]
                )
            } else {
                try db.run("DELETE FROM events WHERE uid = ?", [uid])
            }
        }
    }

    public func deleteDeployTask(id: Int64) throws {
        try db.transaction {
            try db.run("DELETE FROM events WHERE uid = ?", ["deploy:\(id)"])
            try db.run("DELETE FROM deploy_tasks WHERE id = ?", [id])
        }
    }

    // MARK: Epics

    public func epics() throws -> [Epic] {
        try db.query("SELECT id, project_id, name, created_at FROM epics ORDER BY created_at DESC, id DESC") {
            Epic(id: $0.int64(0), projectID: $0.int64(1), name: $0.string(2), createdAt: $0.date(3))
        }
    }

    /// uid do evento → id da epic.
    public func epicMembers() throws -> [String: Int64] {
        Dictionary(
            try db.query("SELECT event_uid, epic_id FROM epic_events") { ($0.string(0), $0.int64(1)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Cria a epic com os eventos e já a coloca na lista de deploy.
    @discardableResult
    public func createEpic(projectID: Int64, name: String, eventUIDs: [String], createdAt: Date = .now) throws -> Epic {
        try db.transaction {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try db.run("INSERT INTO epics (project_id, name, created_at) VALUES (?, ?, ?)", [projectID, clean, createdAt])
            let epic = Epic(id: db.lastInsertID, projectID: projectID, name: clean, createdAt: createdAt)
            try addToEpic(epic.id, eventUIDs: eventUIDs)
            try insertDeployTask(projectID: projectID, kind: .epic, ref: String(epic.id), title: clean, createdAt: createdAt)
            return epic
        }
    }

    /// Move os eventos para a epic (um evento fica em uma epic só).
    public func addToEpic(_ epicID: Int64, eventUIDs: [String]) throws {
        for uid in eventUIDs {
            try db.run("INSERT OR REPLACE INTO epic_events (event_uid, epic_id) VALUES (?, ?)", [uid, epicID])
        }
    }

    public func removeFromEpic(eventUIDs: [String]) throws {
        for uid in eventUIDs {
            try db.run("DELETE FROM epic_events WHERE event_uid = ?", [uid])
        }
    }

    public func renameEpic(id: Int64, to name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.transaction {
            try db.run("UPDATE epics SET name = ? WHERE id = ?", [clean, id])
            try db.run("UPDATE deploy_tasks SET title = ? WHERE kind = ? AND ref = ?", [clean, DeployTask.Kind.epic.rawValue, String(id)])
        }
    }

    /// Apaga a epic e o item dela na lista de deploy; os commits continuam na timeline.
    public func deleteEpic(id: Int64) throws {
        try db.transaction {
            let taskIDs = try db.query("SELECT id FROM deploy_tasks WHERE kind = ? AND ref = ?", [DeployTask.Kind.epic.rawValue, String(id)]) { $0.int64(0) }
            for taskID in taskIDs {
                try db.run("DELETE FROM events WHERE uid = ?", ["deploy:\(taskID)"])
                try db.run("DELETE FROM deploy_tasks WHERE id = ?", [taskID])
            }
            try db.run("DELETE FROM epics WHERE id = ?", [id])
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try db.transaction(body)
    }
}
