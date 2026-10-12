import Foundation

public struct StandupItem: Identifiable, Hashable, Sendable {
    /// Estável entre aberturas: seção + projeto + texto original.
    public let id: String
    public let text: String
}

public struct StandupGroup: Identifiable, Hashable, Sendable {
    public var id: String { project }
    public let project: String
    public let projectID: Int64?
    public let items: [StandupItem]
}

public struct StandupSection: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public let title: String
    public let groups: [StandupGroup]
}

/// Monta o standup: o último dia com atividade antes de hoje e o que já foi feito hoje.
public enum Standup {
    /// Dia mais recente com eventos, estritamente antes de `today`.
    public static func previousActiveDay(before today: Date, in events: [Event], calendar: Calendar = .current) -> Date? {
        recentActiveDays(before: today, in: events, limit: 1, calendar: calendar).first
    }

    /// Os últimos dias com eventos antes de `today`, do mais recente para o mais antigo.
    public static func recentActiveDays(before today: Date, in events: [Event], limit: Int, calendar: Calendar = .current) -> [Date] {
        let todayStart = calendar.startOfDay(for: today)
        let days = Set(events.map { calendar.startOfDay(for: $0.date) }.filter { $0 < todayStart })
        return Array(days.sorted(by: >).prefix(limit))
    }

    public static func sections(
        events: [Event],
        projects: [Int64: Project],
        previousDay: Date?,
        today: Date = .now,
        deploys: [DeployTask] = [],
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [StandupSection] {
        var sections: [StandupSection] = []
        if let previousDay {
            let title = dayTitle(previousDay, today: today, calendar: calendar, locale: locale)
            sections.append(section(title: title, events: on(previousDay, events, calendar), projects: projects))
        }
        let todayEvents = on(today, events, calendar)
        if !todayEvents.isEmpty {
            sections.append(section(title: "Hoje até agora", events: todayEvents, projects: projects))
        }
        sections.append(deploySection(deploys.filter(\.isPending), projects: projects))
        return sections.filter { !$0.groups.isEmpty }
    }

    /// Pendências de deploy agrupadas por projeto.
    static func deploySection(_ tasks: [DeployTask], projects: [Int64: Project]) -> StandupSection {
        let title = "Aguardando deploy"
        var order: [Int64] = []
        var items: [Int64: [String]] = [:]
        for task in tasks {
            if items[task.projectID] == nil { order.append(task.projectID) }
            items[task.projectID, default: []].append(deployLine(task))
        }
        let groups = order.map { id -> StandupGroup in
            let name = projects[id]?.name ?? "Outros"
            return StandupGroup(
                project: name, projectID: id,
                items: items[id, default: []].map { StandupItem(id: "\(title)|\(name)|\($0)", text: $0) }
            )
        }
        return StandupSection(title: title, groups: groups)
    }

    static func deployLine(_ task: DeployTask) -> String {
        switch task.kind {
        case .branch: return "Branch \(task.ref ?? task.title)"
        case .pullRequest:
            guard let ref = task.ref else { return task.title }
            return "\(ref.hasPrefix("!") ? "MR" : "PR") \(ref): \(task.title)"
        case .epic: return "Epic \(task.title)"
        case .commit, .text: return task.title
        }
    }

    public struct Rendered: Equatable, Sendable {
        public let plain: String
        public let html: String
        public let itemCount: Int
        public let projectCount: Int
    }

    /// Texto final, sem os itens desmarcados, com as edições e as seções livres (ex: "Hoje vou").
    public static func render(
        _ sections: [StandupSection],
        excluded: Set<String> = [],
        edits: [String: String] = [:],
        extras: [(title: String, text: String)] = []
    ) -> Rendered {
        var plain: [String] = []
        var html: [String] = []
        var itemCount = 0
        var projectNames = Set<String>()

        for section in sections {
            let groups = section.groups.compactMap { group -> (String, [String])? in
                let items = group.items
                    .filter { !excluded.contains($0.id) }
                    .map { (edits[$0.id] ?? $0.text).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return items.isEmpty ? nil : (group.project, items)
            }
            guard !groups.isEmpty else { continue }

            plain.append(([section.title] + groups.map { project, items in
                ([project] + items.map { "- \($0)" }).joined(separator: "\n")
            }).joined(separator: "\n\n"))
            html.append("<p><b>\(escape(section.title))</b></p>" + groups.map { project, items in
                "<p>\(escape(project))</p><ul>" + items.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
            }.joined())

            itemCount += groups.reduce(0) { $0 + $1.1.count }
            projectNames.formUnion(groups.map(\.0))
        }

        for extra in extras {
            let lines = extra.text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            plain.append(([extra.title] + lines.map { "- \($0)" }).joined(separator: "\n"))
            html.append("<p><b>\(escape(extra.title))</b></p><ul>" + lines.map { "<li>\(escape($0))</li>" }.joined() + "</ul>")
        }

        return Rendered(
            plain: plain.isEmpty ? "Nada registrado." : plain.joined(separator: "\n\n"),
            html: html.joined(),
            itemCount: itemCount,
            projectCount: projectNames.count
        )
    }

    /// Atalho: tudo incluído, sem edições.
    public static func text(
        events: [Event],
        projects: [Int64: Project],
        previousDay: Date?,
        today: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        render(sections(events: events, projects: projects, previousDay: previousDay, today: today, calendar: calendar, locale: locale)).plain
    }

    /// "Ontem" ou, para dias mais antigos, "Sexta-feira, 09/10".
    public static func dayTitle(_ day: Date, today: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today)),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Ontem"
        }
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.twoDigits)
        let text = day.formatted(style)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func on(_ day: Date, _ events: [Event], _ calendar: Calendar) -> [Event] {
        events.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
    }

    /// Um grupo por projeto, na ordem do primeiro evento do dia. PRs vêm primeiro; itens repetidos aparecem uma vez,
    /// e PRs com o mesmo título e estado viram uma linha só (ex: MR da feature e MR de promoção para outra branch).
    static func section(title: String, events: [Event], projects: [Int64: Project]) -> StandupSection {
        struct Bucket {
            var id: Int64?
            var prKeys: [String] = []
            var prRefs: [String: [String]] = [:]
            var items: [String] = []
        }
        var order: [String] = []
        var buckets: [String: Bucket] = [:]

        for event in events {
            let project = event.projectID.flatMap { projects[$0] }
            let name = project?.name ?? "Outros"
            if buckets[name] == nil {
                order.append(name)
                buckets[name] = Bucket(id: project?.id)
            }
            switch event.kind {
            case .pullRequest:
                // Título de PR é uma frase só: não corta no " - " como nos commits.
                let key = "\(event.state ?? "")|\(CommitMessage.parse(event.title).text)"
                if buckets[name]!.prRefs[key] == nil { buckets[name]!.prKeys.append(key) }
                let ref = event.ref ?? ""
                if !buckets[name]!.prRefs[key, default: []].contains(ref) { buckets[name]!.prRefs[key, default: []].append(ref) }
            case .commit, .note, .deploy:
                let item: String
                switch event.kind {
                case .commit: item = CommitMessage.parse(event.title).headline
                case .deploy: item = "Deploy: \(event.title)"
                default: item = event.displayTitle
                }
                if !buckets[name]!.items.contains(item) { buckets[name]!.items.append(item) }
            }
        }

        let groups = order.map { name -> StandupGroup in
            let bucket = buckets[name]!
            let prHeadlines = Set(bucket.prKeys.map { String($0.split(separator: "|", maxSplits: 1).last ?? "") })
            let prItems = bucket.prKeys.map { key -> String in
                let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                return pullRequestLine(refs: bucket.prRefs[key, default: []], state: parts[0], headline: parts[1])
            }
            // Commit com o mesmo título de um PR do dia já está representado pelo PR.
            let texts = prItems + bucket.items.filter { item in !prHeadlines.contains { $0 == item || $0.hasPrefix(item + " - ") } }
            return StandupGroup(
                project: name,
                projectID: bucket.id,
                items: texts.map { StandupItem(id: "\(title)|\(name)|\($0)", text: $0) }
            )
        }
        return StandupSection(title: title, groups: groups)
    }

    /// "PR #72 mergeado: X", "MRs !65 e !66 mergeados: Y".
    static func pullRequestLine(refs: [String], state: String, headline: String) -> String {
        let plural = refs.count > 1
        let noun = refs.allSatisfy { $0.hasPrefix("!") } ? "MR" : "PR"
        let verb: String
        switch state {
        case "open": verb = "aberto"
        case "closed": verb = "fechado"
        default: verb = "mergeado"
        }
        let list = refs.count > 1 ? refs.dropLast().joined(separator: ", ") + " e " + refs.last! : (refs.first ?? "")
        return "\(noun)\(plural ? "s" : "") \(list) \(verb)\(plural ? "s" : ""): \(headline)"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
