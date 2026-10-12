import Foundation
import Testing
@testable import RastroCore

struct StandupTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()
    let locale = Locale(identifier: "pt_BR")
    let projects: [Int64: Project] = [
        1: Project(id: 1, path: "/r/api", name: "api", colorHex: "#2a78d6"),
        2: Project(id: 2, path: "/r/site", name: "site", colorHex: "#eb6834"),
    ]

    func at(_ day: Int, _ hour: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func commit(_ id: Int64, _ date: Date, _ title: String, project: Int64?) -> Event {
        Event(id: id, uid: "c\(id)", kind: .commit, date: date, title: title, projectID: project)
    }

    @Test func previousActiveDaySkipsGaps() {
        let events = [commit(1, at(9, 10), "a", project: 1), commit(2, at(5, 10), "b", project: 1), commit(3, at(12, 9), "c", project: 1)]
        #expect(Standup.previousActiveDay(before: at(12, 15), in: events, calendar: calendar) == calendar.startOfDay(for: at(9, 1)))
        #expect(Standup.previousActiveDay(before: at(5, 15), in: events, calendar: calendar) == nil)
    }

    @Test func groupsByProjectAndDeduplicates() {
        let events = [
            commit(1, at(11, 9), "feat: Cria tela - Ajusta rota", project: 1),
            commit(2, at(11, 10), "fix: Corrige header", project: 2),
            commit(3, at(11, 11), "FEAT: Cria tela - Outra coisa", project: 1),
            Event(id: 4, uid: "n4", kind: .note, date: at(11, 14), title: "Call com cliente", projectID: nil),
            commit(5, at(12, 8), "Atualiza README", project: 2),
        ]
        let text = Standup.text(events: events, projects: projects, previousDay: at(11, 0), today: at(12, 9), calendar: calendar, locale: locale)
        #expect(text == """
        Ontem

        api
        - Cria tela

        site
        - Corrige header

        Outros
        - Call com cliente

        Hoje até agora

        site
        - Atualiza README
        """)
    }

    @Test func namesOlderDayByWeekday() {
        let events = [commit(1, at(9, 9), "Ajusta deploy", project: 1)]
        let text = Standup.text(events: events, projects: projects, previousDay: at(9, 0), today: at(12, 9), calendar: calendar, locale: locale)
        #expect(text.hasPrefix("Sexta-feira, 09/10"))
        #expect(!text.contains("Hoje até agora"))
    }

    @Test func emptyWhenNothingHappened() {
        #expect(Standup.text(events: [], projects: projects, previousDay: nil, today: at(12, 9), calendar: calendar, locale: locale) == "Nada registrado.")
    }

    @Test func recentActiveDaysAreDistinctAndOrdered() {
        let events = [commit(1, at(9, 10), "a", project: 1), commit(2, at(9, 12), "b", project: 1),
                      commit(3, at(5, 10), "c", project: 1), commit(4, at(12, 9), "d", project: 1)]
        let days = Standup.recentActiveDays(before: at(12, 15), in: events, limit: 5, calendar: calendar)
        #expect(days == [calendar.startOfDay(for: at(9, 1)), calendar.startOfDay(for: at(5, 1))])
    }

    @Test func renderHonorsExclusionsEditsAndExtras() throws {
        let events = [
            commit(1, at(11, 9), "feat: Cria tela", project: 1),
            commit(2, at(11, 10), "fix: Corrige <header> & menu", project: 2),
            commit(3, at(11, 11), "Remove log", project: 2),
        ]
        let sections = Standup.sections(events: events, projects: projects, previousDay: at(11, 0), today: at(12, 9), calendar: calendar, locale: locale)
        let api = try #require(sections.first?.groups.first?.items.first)
        let removeLog = try #require(sections.first?.groups.last?.items.last)

        let rendered = Standup.render(
            sections,
            excluded: [removeLog.id],
            edits: [api.id: "Cria tela de login  "],
            extras: [("Hoje vou", "- Revisar PR\n\nSubir deploy"), ("Bloqueios", "  \n")]
        )
        #expect(rendered.plain == """
        Ontem

        api
        - Cria tela de login

        site
        - Corrige <header> & menu

        Hoje vou
        - Revisar PR
        - Subir deploy
        """)
        #expect(rendered.html.contains("<li>Corrige &lt;header&gt; &amp; menu</li>"))
        #expect(rendered.html.hasPrefix("<p><b>Ontem</b></p><p>api</p><ul><li>Cria tela de login</li></ul>"))
        #expect(!rendered.html.contains("Bloqueios"))
        #expect(rendered.itemCount == 2)
        #expect(rendered.projectCount == 2)
    }

    @Test func excludingEveryItemDropsTheSection() {
        let events = [commit(1, at(11, 9), "Cria tela", project: 1)]
        let sections = Standup.sections(events: events, projects: projects, previousDay: at(11, 0), today: at(12, 9), calendar: calendar, locale: locale)
        let all = Set(sections.flatMap(\.groups).flatMap(\.items).map(\.id))
        #expect(Standup.render(sections, excluded: all).plain == "Nada registrado.")
    }

    @Test func pullRequestsComeFirstAndMergeSameTitle() {
        func pr(_ id: Int64, _ hour: Int, _ ref: String, _ state: String, _ title: String) -> Event {
            Event(id: id, uid: "p\(id)", kind: .pullRequest, date: at(11, hour), title: title, projectID: 1, ref: ref, state: state)
        }
        let events = [
            commit(1, at(11, 9), "[BUGFIX] Correção prévia - Painéis", project: 1),
            pr(2, 10, "!65", "merged", "[BUGFIX] Correção prévia - Painéis"),
            pr(3, 11, "!66", "merged", "[BUGFIX] Correção prévia - Painéis"),
            pr(4, 12, "#72", "open", "FEAT: Ajustar transportadora"),
            commit(5, at(11, 13), "Remove log", project: 1),
        ]
        let text = Standup.text(events: events, projects: projects, previousDay: at(11, 0), today: at(12, 9), calendar: calendar, locale: locale)
        #expect(text == """
        Ontem

        api
        - MRs !65 e !66 mergeados: Correção prévia - Painéis
        - PR #72 aberto: Ajustar transportadora
        - Remove log
        """)
    }

    @Test func noteWithoutTitleUsesFirstLineOfText() {
        let untitled = Event(id: 1, uid: "n1", kind: .note, date: at(11, 9), title: "", detail: "Call com a Acme\nFalamos de remessas", projectID: 1)
        let titled = Event(id: 2, uid: "n2", kind: .note, date: at(11, 10), title: "Reunião", detail: "Pauta longa", projectID: 1)
        #expect(untitled.displayTitle == "Call com a Acme")
        #expect(titled.displayTitle == "Reunião")
        let text = Standup.text(events: [untitled, titled], projects: projects, previousDay: at(11, 0), today: at(12, 9), calendar: calendar, locale: locale)
        #expect(text.contains("- Call com a Acme\n- Reunião"))
    }
}
