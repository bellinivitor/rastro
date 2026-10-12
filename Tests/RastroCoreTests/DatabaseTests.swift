import Foundation
import Testing
@testable import RastroCore

struct DatabaseTests {
    let db: Database

    init() throws {
        db = try Database(path: ":memory:")
    }

    func commit(_ hash: String, _ date: String, _ subject: String = "msg") -> RawCommit {
        RawCommit(hash: hash, authorName: "Eu", authorEmail: "eu@x.com", date: ISO8601DateFormatter().date(from: date)!, subject: subject)
    }

    @Test func importCreatesProjectsAndEvents() throws {
        let repos = [
            ScannedRepo(path: "/r/api", name: "api", commits: [commit("a", "2026-10-01T10:00:00Z"), commit("b", "2026-10-03T10:00:00Z")]),
            ScannedRepo(path: "/r/site", name: "site", commits: []),
        ]
        let inserted = try Importer(database: db, palette: ["#111111", "#222222"]).importRepos(repos)
        #expect(inserted == 2)

        let projects = try db.projects()
        #expect(projects.map(\.name) == ["api", "site"])
        #expect(projects.map(\.colorHex) == ["#111111", "#222222"])
        #expect(projects[0].lastCommitAt == ISO8601DateFormatter().date(from: "2026-10-03T10:00:00Z"))
        #expect(projects[0].lastScannedAt != nil)
        #expect(projects[1].lastCommitAt == nil)

        let events = try db.events()
        #expect(events.map(\.uid) == ["commit:/r/api#b", "commit:/r/api#a"])
        #expect(events.allSatisfy { $0.projectID == projects[0].id && $0.kind == .commit })
    }

    @Test func reimportDeduplicatesAndKeepsNewestCommit() throws {
        let importer = Importer(database: db, palette: [])
        try importer.importRepos([ScannedRepo(path: "/r/api", name: "api", commits: [commit("a", "2026-10-05T10:00:00Z")])])
        // Escaneamento incremental devolve o mesmo commit e um mais antigo pulado antes.
        let again = try importer.importRepos([ScannedRepo(path: "/r/api", name: "api", commits: [
            commit("a", "2026-10-05T10:00:00Z"), commit("z", "2026-09-01T10:00:00Z"),
        ])])
        #expect(again == 1)
        #expect(try db.events().count == 2)
        #expect(try db.projects().count == 1)
        #expect(try db.projects().first?.lastCommitAt == ISO8601DateFormatter().date(from: "2026-10-05T10:00:00Z"))
    }

    @Test func notesRoundTripAndDelete() throws {
        let date = Date(timeIntervalSince1970: 1_760_000_000.5)
        #expect(try db.insertEvent(uid: "note:1", kind: .note, date: date, title: "Reunião", detail: "com cliente"))
        #expect(try db.insertEvent(uid: "note:1", kind: .note, date: date, title: "duplicada") == false)

        let note = try #require(db.events().first)
        #expect(note.kind == .note)
        #expect(note.title == "Reunião")
        #expect(note.detail == "com cliente")
        #expect(note.date == date)
        #expect(note.projectID == nil)
        #expect(note.author == nil)

        try db.deleteEvent(id: note.id)
        #expect(try db.events().isEmpty)
    }

    @Test func migrationIsIdempotentOnDisk() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("rastro-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Database(path: path).insertEvent(uid: "note:x", kind: .note, date: .now, title: "persistida")
        let reopened = try Database(path: path)
        #expect(try reopened.events().map(\.title) == ["persistida"])
    }

    @Test func failedTransactionRollsBack() throws {
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try db.transaction {
                try db.insertEvent(uid: "note:x", kind: .note, date: .now, title: "some")
                throw Boom()
            }
        }
        #expect(try db.events().isEmpty)
    }

    @Test func editsNotesButNeverCommits() throws {
        let project = try db.insertProject(path: "/r/api", name: "api", colorHex: "#2a78d6")
        try db.insertEvent(uid: "note:1", kind: .note, date: .now, title: "Reunião", detail: nil)
        try db.insertEvent(uid: "commit:/r/api#a", kind: .commit, date: .now, title: "feat: x", projectID: project.id)
        let events = try db.events()
        let note = try #require(events.first { $0.kind == .note })
        let commit = try #require(events.first { $0.kind == .commit })
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        try db.updateNote(id: note.id, title: "Reunião com a Acme", detail: "Fluxo de remessas", date: newDate, projectID: project.id)
        try db.updateNote(id: commit.id, title: "hackeado", detail: nil, date: newDate, projectID: nil)

        let after = try db.events()
        let edited = try #require(after.first { $0.id == note.id })
        #expect(edited.title == "Reunião com a Acme")
        #expect(edited.detail == "Fluxo de remessas")
        #expect(edited.date == newDate)
        #expect(edited.projectID == project.id)
        #expect(after.first { $0.id == commit.id }?.title == "feat: x")
    }
}
