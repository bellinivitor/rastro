import Foundation
import Testing
@testable import DevTimelineCore

struct ProjectSettingsTests {
    @Test func settingsRoundTripAndSurviveRescan() throws {
        let db = try Database(path: ":memory:")
        let importer = Importer(database: db, palette: ["#2a78d6"])
        try importer.importRepos([ScannedRepo(path: "/r/front", name: "frontend", commits: [])])

        var project = try #require(db.projects().first)
        #expect(!project.isFavorite && !project.isHidden && project.groupID == nil)

        let cliente = try db.group(named: "Cliente")
        project.name = "Cliente Frontend"
        project.colorHex = "#e34948"
        project.isFavorite = true
        project.isHidden = true
        project.groupID = cliente.id
        try db.updateSettings(project)

        // Escanear de novo não pode desfazer o que o usuário configurou.
        try importer.importRepos([ScannedRepo(path: "/r/front", name: "frontend", commits: [])])
        let saved = try #require(db.projects().first)
        #expect(saved.name == "Cliente Frontend")
        #expect(saved.colorHex == "#e34948")
        #expect(saved.isFavorite && saved.isHidden)
        #expect(saved.groupID == cliente.id)
    }

    @Test func groupsAreUniqueByNameAndDeletingKeepsProjects() throws {
        let db = try Database(path: ":memory:")
        let first = try db.group(named: "Acme")
        let again = try db.group(named: "  acme ")
        #expect(first.id == again.id)

        var project = try db.insertProject(path: "/r/tc", name: "loja-api", colorHex: "#eb6834")
        project.groupID = first.id
        try db.updateSettings(project)

        try db.renameGroup(id: first.id, to: "Acme Loja")
        #expect(try db.groups().map(\.name) == ["Acme Loja"])

        try db.deleteGroup(id: first.id)
        #expect(try db.groups().isEmpty)
        #expect(try db.projects().first?.groupID == nil)
        #expect(try db.projects().count == 1)
    }
}
