import Foundation
import Testing
@testable import DevTimelineCore

struct EpicTests {
    let db: Database
    let project: Project

    init() throws {
        db = try Database(path: ":memory:")
        project = try db.insertProject(path: "/r/tc", name: "loja-api", colorHex: "#eb6834")
        for (uid, title) in [("commit:/r/tc#a", "feat: relatório mensal"), ("commit:/r/tc#b", "fix: timezone"), ("commit:/r/tc#c", "Remove log")] {
            try db.insertEvent(uid: uid, kind: .commit, date: .now, title: title, projectID: project.id)
        }
    }

    @Test func createEpicPutsItOnTheDeployList() throws {
        let epic = try db.createEpic(projectID: project.id, name: "  Checkout ", eventUIDs: ["commit:/r/tc#a", "commit:/r/tc#b"])
        #expect(epic.name == "Checkout")
        #expect(try db.epics().map(\.name) == ["Checkout"])
        #expect(try db.epicMembers() == ["commit:/r/tc#a": epic.id, "commit:/r/tc#b": epic.id])

        let task = try #require(db.deployTasks().first)
        #expect(task.kind == .epic)
        #expect(task.ref == String(epic.id))
        #expect(task.title == "Checkout")
        #expect(task.isPending)
    }

    @Test func eventBelongsToOneEpicAtATime() throws {
        let first = try db.createEpic(projectID: project.id, name: "A", eventUIDs: ["commit:/r/tc#a"])
        let second = try db.createEpic(projectID: project.id, name: "B", eventUIDs: ["commit:/r/tc#b"])
        try db.addToEpic(second.id, eventUIDs: ["commit:/r/tc#a"])
        #expect(try db.epicMembers()["commit:/r/tc#a"] == second.id)
        #expect(try !db.epicMembers().values.contains(first.id))

        try db.removeFromEpic(eventUIDs: ["commit:/r/tc#a"])
        #expect(try db.epicMembers() == ["commit:/r/tc#b": second.id])
    }

    @Test func deployingTheEpicClearsLooseRemindersOfItsCommits() throws {
        try db.insertDeployTask(projectID: project.id, kind: .commit, ref: "a", title: "relatório mensal", eventUID: "commit:/r/tc#a")
        try db.insertDeployTask(projectID: project.id, kind: .commit, ref: "c", title: "Remove log", eventUID: "commit:/r/tc#c")
        try db.createEpic(projectID: project.id, name: "Checkout", eventUIDs: ["commit:/r/tc#a", "commit:/r/tc#b"])
        let epicTask = try #require(db.deployTasks().first { $0.kind == .epic })

        try db.setDeployed(epicTask, at: .now)

        let tasks = try db.deployTasks()
        #expect(tasks.map(\.title).sorted() == ["Checkout", "Remove log"])
        #expect(tasks.first { $0.kind == .epic }?.isPending == false)
        #expect(try db.events().first { $0.kind == .deploy }?.title == "Epic Checkout")
    }

    @Test func renameAndDeleteKeepDeployListInSync() throws {
        let epic = try db.createEpic(projectID: project.id, name: "Checkout", eventUIDs: ["commit:/r/tc#a"])
        try db.renameEpic(id: epic.id, to: "Checkout v2")
        #expect(try db.deployTasks().first?.title == "Checkout v2")

        try db.setDeployed(try #require(db.deployTasks().first), at: .now)
        try db.deleteEpic(id: epic.id)
        #expect(try db.epics().isEmpty)
        #expect(try db.deployTasks().isEmpty)
        #expect(try db.epicMembers().isEmpty)
        #expect(try db.events().filter { $0.kind == .deploy }.isEmpty)
        #expect(try db.events().count == 3)
    }

    @Test func standupShowsEpicAsOneLine() {
        let projects = [project.id: project]
        let task = DeployTask(id: 1, projectID: project.id, kind: .epic, ref: "1", title: "Checkout", eventUID: nil, createdAt: .now)
        let text = Standup.render(Standup.sections(events: [], projects: projects, previousDay: nil, deploys: [task])).plain
        #expect(text.contains("- Epic Checkout"))
    }
}
