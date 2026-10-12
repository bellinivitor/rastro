import Foundation
import Testing
@testable import DevTimelineCore

struct DeployTaskDatabaseTests {
    @Test func roundTripMarkDoneAndReopen() throws {
        let db = try Database(path: ":memory:")
        let project = try db.insertProject(path: "/r/api", name: "api", colorHex: "#2a78d6")
        let created = Date(timeIntervalSince1970: 1_760_000_000)
        let task = try db.insertDeployTask(projectID: project.id, kind: .pullRequest, ref: "#81", title: "Gerar relatório mensal", eventUID: "pr:x#81:merged", createdAt: created)
        try db.insertDeployTask(projectID: project.id, kind: .text, ref: nil, title: "Rodar migration")

        #expect(try db.deployTasks().map(\.title) == ["Rodar migration", "Gerar relatório mensal"])
        #expect(try db.deployTasks().allSatisfy(\.isPending))

        let doneAt = created.addingTimeInterval(3600)
        try db.setDeployed(task, at: doneAt)
        let deploy = try #require(db.events().first { $0.kind == .deploy })
        #expect(deploy.uid == "deploy:\(task.id)")
        #expect(deploy.title == "Gerar relatório mensal")
        #expect(deploy.ref == "#81")
        #expect(deploy.date == doneAt)
        #expect(try db.deployTasks().last?.doneAt == doneAt)

        try db.setDeployed(task, at: nil)
        #expect(try db.events().isEmpty)
        #expect(try db.deployTasks().allSatisfy(\.isPending))
    }

    @Test func deleteRemovesTaskAndItsEvent() throws {
        let db = try Database(path: ":memory:")
        let project = try db.insertProject(path: "/r/api", name: "api", colorHex: "#2a78d6")
        let task = try db.insertDeployTask(projectID: project.id, kind: .branch, ref: "fix/x", title: "fix/x")
        try db.setDeployed(task, at: .now)
        #expect(try db.events().first?.title == "Branch fix/x")
        try db.deleteDeployTask(id: task.id)
        #expect(try db.events().isEmpty)
        #expect(try db.deployTasks().isEmpty)
    }

    @Test func draftFromTimelineEvents() {
        let commit = Event(id: 1, uid: "commit:/r/api#abc123", kind: .commit, date: .now, title: "FEAT: Cria tela - Ajusta rota")
        #expect(DeployTask.draft(from: commit)?.ref == "abc123")
        #expect(commit.commitHash == "abc123")
        #expect(DeployTask.draft(from: commit)?.title == "Cria tela")
        let pr = Event(id: 2, uid: "pr:x#7:merged", kind: .pullRequest, date: .now, title: "[BUGFIX] Correção - Painéis", ref: "!7")
        #expect(DeployTask.draft(from: pr)?.title == "Correção - Painéis")
        #expect(DeployTask.draft(from: pr)?.kind == .pullRequest)
        #expect(DeployTask.draft(from: Event(id: 3, uid: "note:1", kind: .note, date: .now, title: "x")) == nil)
    }
}

struct DeployStandupTests {
    @Test func pendingDeploysBecomeTheirOwnSection() {
        let projects: [Int64: Project] = [1: Project(id: 1, path: "/r/api", name: "api", colorHex: "#2a78d6")]
        let tasks = [
            DeployTask(id: 1, projectID: 1, kind: .pullRequest, ref: "!66", title: "Correção prévia", eventUID: nil, createdAt: .now),
            DeployTask(id: 2, projectID: 1, kind: .branch, ref: "fix/x", title: "fix/x", eventUID: nil, createdAt: .now),
            DeployTask(id: 3, projectID: 1, kind: .text, ref: nil, title: "Rodar migration", eventUID: nil, createdAt: .now),
            DeployTask(id: 4, projectID: 1, kind: .text, ref: nil, title: "Já feito", eventUID: nil, createdAt: .now, doneAt: .now),
        ]
        let text = Standup.render(Standup.sections(events: [], projects: projects, previousDay: nil, deploys: tasks)).plain
        #expect(text == """
        Aguardando deploy

        api
        - MR !66: Correção prévia
        - Branch fix/x
        - Rodar migration
        """)
    }
}

struct DeployTagTests {
    @Test(arguments: [
        ("feat: Cria tela [deploy]", "feat", "Cria tela"),
        ("[DEPLOY] fix: Corrige header", "fix", "Corrige header"),
        ("Ajusta rota #deploy - Remove log", nil, "Ajusta rota - Remove log"),
    ] as [(String, String?, String)])
    func detectsAndStripsTag(subject: String, type: String?, text: String) {
        let message = CommitMessage.parse(subject)
        #expect(message.wantsDeploy)
        #expect(message.type == type)
        #expect(message.text == text)
    }

    @Test func ignoresLookalikes() {
        #expect(!CommitMessage.parse("Documenta #deployment no README").wantsDeploy)
        #expect(!CommitMessage.parse("Ajusta deploy do Forge").wantsDeploy)
    }

    @Test func importerCreatesReminderOnceForTaggedWork() throws {
        let db = try Database(path: ":memory:")
        let importer = Importer(database: db, palette: [])
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let tagged = RawCommit(hash: "abc123", authorName: "Eu", authorEmail: "eu@x.com", date: date, subject: "feat: Cria tela [deploy]")
        let plain = RawCommit(hash: "def456", authorName: "Eu", authorEmail: "eu@x.com", date: date, subject: "Remove log")
        let pr = RawPullRequest(repo: "github.com/a/b", number: 9, title: "FEAT: Nova API #deploy", state: .merged, date: date)
        let repo = ScannedRepo(path: "/r/api", name: "api", commits: [tagged, plain], remote: "github.com/a/b", pullRequests: [pr])

        try importer.importRepos([repo])
        var tasks = try db.deployTasks()
        #expect(tasks.map(\.title).sorted() == ["Cria tela", "Nova API"])
        #expect(tasks.first { $0.kind == .commit }?.ref == "abc123")
        #expect(tasks.first { $0.kind == .pullRequest }?.ref == "#9")

        // Apagou o lembrete e escaneou de novo: não volta.
        try db.deleteDeployTask(id: tasks[0].id)
        try importer.importRepos([repo])
        tasks = try db.deployTasks()
        #expect(tasks.count == 1)
    }
}
