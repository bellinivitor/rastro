import Foundation
import RastroCore

/// Dados fictícios do modo demonstração: uma loja de exemplo (Acme), um blog e a infra.
/// Gerados a partir de hoje, com sorteio de semente fixa, para o print ser sempre parecido.
enum DemoData {
    private struct Generator {
        var state: UInt64 = 0x5EED_1234
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
        mutating func chance(_ p: Double) -> Bool { Double(next() % 1000) / 1000 < p }
        mutating func hex() -> String { String(format: "%08x%08x", UInt32(truncatingIfNeeded: next()), UInt32(truncatingIfNeeded: next())) }
    }

    private static let messages: [String: [String]] = [
        "loja-api": [
            "feat(checkout): suporta cupom de primeira compra",
            "fix: corrige arredondamento do desconto no carrinho",
            "feat: adiciona cálculo de frete por região - Tabela por CEP - Fallback para valor padrão",
            "refactor: extrai serviço de pagamentos - Move validação para o serviço - Adiciona testes de integração",
            "perf: cacheia catálogo de produtos por 5 minutos",
            "fix: evita pedido duplicado em clique duplo",
            "test: cobre estorno parcial",
            "feat: webhook de pagamento aprovado",
            "chore: atualiza dependências",
        ],
        "loja-web": [
            "feat: nova página de carrinho",
            "fix: corrige header no mobile",
            "feat: mostra prazo de entrega no produto",
            "style: ajusta espaçamento dos cards",
            "refactor: componentes de formulário compartilhados",
            "fix: foco perdido no campo de CEP",
        ],
        "app-mobile": [
            "feat: login com biometria",
            "fix: crash ao abrir notificação antiga",
            "feat: acompanhamento do pedido em tempo real",
            "perf: reduz tamanho das imagens da vitrine",
        ],
        "infra": [
            "chore: atualiza imagem do PHP para 8.4",
            "ci: roda testes em paralelo",
            "feat: backup diário do banco",
        ],
        "blog": [
            "docs: post sobre filas no Laravel",
            "docs: corrige exemplos do post de cache",
            "feat: busca no blog",
        ],
    ]

    static func seed(_ db: Database) throws {
        var random = Generator()
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)

        // Projetos, cores da paleta e o grupo do cliente.
        let palette = ["#2a78d6", "#eb6834", "#1baf7a", "#4a3aa7", "#e87ba4"]
        var projects: [String: Project] = [:]
        for (index, name) in ["loja-api", "loja-web", "app-mobile", "infra", "blog"].enumerated() {
            projects[name] = try db.insertProject(path: "/demo/\(name)", name: name, colorHex: palette[index])
        }
        let acme = try db.group(named: "Acme")
        for name in ["loja-api", "loja-web", "app-mobile"] {
            var project = projects[name]!
            project.groupID = acme.id
            try db.updateSettings(project)
        }
        var blog = projects["blog"]!
        blog.isFavorite = true
        try db.updateSettings(blog)

        func date(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        // Commits dos últimos ~4 meses, mais intensos nas últimas semanas, com sequência até hoje.
        var commitUIDs: [String: [String]] = [:]
        for daysAgo in (0...120).reversed() {
            let recent = daysAgo < 42
            let weekday = calendar.component(.weekday, from: calendar.date(byAdding: .day, value: -daysAgo, to: today)!)
            let weekend = weekday == 1 || weekday == 7
            let active = daysAgo < 9 || random.chance(weekend ? 0.12 : (recent ? 0.8 : 0.35))
            guard active else { continue }
            var usedToday = Set<String>()
            for _ in 0..<random.int(recent ? 2...6 : 1...3) {
                let name = ["loja-api", "loja-api", "loja-web", "app-mobile", "infra", "blog"][random.int(0...5)]
                let options = messages[name]!.filter { !usedToday.contains($0) }
                guard !options.isEmpty else { continue }
                var hour = random.int(9...19)
                if daysAgo == 0 { hour = min(hour, max(9, calendar.component(.hour, from: now) - 1)) }
                let when = date(daysAgo: daysAgo, hour: hour, minute: random.int(0...59))
                let uid = "commit:/demo/\(name)#\(random.hex())"
                let message = options[random.int(0...options.count - 1)]
                usedToday.insert(message)
                try db.insertEvent(uid: uid, kind: .commit, date: when, title: message,
                                   author: "dev@exemplo.com", projectID: projects[name]!.id)
                commitUIDs[name, default: []].append(uid)
            }
        }

        // PRs do GitHub e MRs do GitLab.
        let pullRequests: [(String, String, String, String, Int, String?)] = [
            ("loja-api", "#52", "feat(checkout): cupom de primeira compra", "open", 1, nil),
            ("loja-api", "#49", "fix: pedido duplicado em clique duplo", "merged", 2, nil),
            ("loja-web", "#31", "feat: nova página de carrinho", "merged", 3, nil),
            ("app-mobile", "#18", "feat: login com biometria", "open", 4, nil),
            ("infra", "!12", "chore: PHP 8.4 em produção", "merged", 1, "feat/php-84 → main"),
            ("infra", "!11", "ci: testes em paralelo", "merged", 6, "ci/paralelo → main"),
        ]
        for (name, ref, title, state, daysAgo, branches) in pullRequests {
            let number = ref.dropFirst()
            let url = ref.hasPrefix("!")
                ? "https://gitlab.exemplo.com/acme/\(name)/-/merge_requests/\(number)"
                : "https://github.com/acme/\(name)/pull/\(number)"
            try db.insertEvent(
                uid: "pr:demo/\(name)\(ref):\(state)", kind: .pullRequest, date: date(daysAgo: daysAgo, hour: 16, minute: 20),
                title: title, detail: branches, projectID: projects[name]!.id, ref: ref, state: state, url: url
            )
        }

        // Notas.
        try db.insertEvent(uid: "note:demo-1", kind: .note, date: date(daysAgo: 0, hour: 10, minute: 0), title: "",
                           detail: "Reunião com o time de produto: cupom de primeira compra sai nesta sprint",
                           projectID: projects["loja-api"]!.id)
        try db.insertEvent(uid: "note:demo-2", kind: .note, date: date(daysAgo: 2, hour: 15, minute: 30),
                           title: "Investigação do pedido duplicado",
                           detail: "Duas requisições chegavam em 40 ms. Resolvido com trava por pedido.",
                           projectID: projects["loja-api"]!.id)

        // Deploy: uma tarefa solta, um commit marcado e uma epic.
        try db.insertDeployTask(projectID: projects["loja-api"]!.id, kind: .text, ref: nil,
                                title: "Rodar migration de cupons em produção", createdAt: date(daysAgo: 1, hour: 18, minute: 0))
        if let uid = commitUIDs["app-mobile"]?.last {
            try db.insertDeployTask(projectID: projects["app-mobile"]!.id, kind: .commit, ref: String(uid.split(separator: "#").last!),
                                    title: "Crash ao abrir notificação antiga", eventUID: uid, createdAt: date(daysAgo: 1, hour: 11, minute: 0))
        }
        try db.createEpic(projectID: projects["loja-web"]!.id, name: "Carrinho novo",
                          eventUIDs: Array((commitUIDs["loja-web"] ?? []).suffix(4)), createdAt: date(daysAgo: 2, hour: 9, minute: 0))

        // Rascunho do standup.
        let defaults = AppSettings.defaults
        defaults.set(Date.now.formatted(.iso8601.year().month().day()), forKey: "standup.draftDay")
        defaults.set("Revisar o PR #52 do cupom\nAcompanhar o deploy do carrinho novo", forKey: "standup.plans")
        defaults.set("dev@exemplo.com", forKey: AppSettings.authorEmailsKey)
    }
}
