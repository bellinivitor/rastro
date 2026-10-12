import Foundation

/// Único ponto que grava eventos importados no banco. Deduplica por `uid` (UNIQUE + INSERT OR IGNORE).
public struct Importer {
    let database: Database
    let palette: [String]

    public init(database: Database, palette: [String]) {
        self.database = database
        self.palette = palette
    }

    public static func commitUID(repoPath: String, hash: String) -> String {
        "commit:\(repoPath)#\(hash)"
    }

    /// Retorna quantos eventos novos foram gravados.
    @discardableResult
    public func importRepos(_ repos: [ScannedRepo], now: Date = .now) throws -> Int {
        try database.transaction {
            var projects = Dictionary(try database.projects().map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            var inserted = 0

            for repo in repos {
                let project = try projects[repo.path] ?? {
                    let color = palette.isEmpty ? "#808080" : palette[projects.count % palette.count]
                    let new = try database.insertProject(path: repo.path, name: repo.name, colorHex: color)
                    projects[repo.path] = new
                    return new
                }()

                for commit in repo.commits {
                    let uid = Self.commitUID(repoPath: repo.path, hash: commit.hash)
                    let wrote = try database.insertEvent(
                        uid: uid, kind: .commit, date: commit.date, title: commit.subject,
                        author: commit.authorEmail, projectID: project.id
                    )
                    guard wrote else { continue }
                    inserted += 1
                    // Só na primeira importação: apagar o lembrete depois não o recria.
                    let message = CommitMessage.parse(commit.subject)
                    if message.wantsDeploy {
                        try database.insertDeployTask(
                            projectID: project.id, kind: .commit, ref: commit.hash,
                            title: message.headline, eventUID: uid, createdAt: commit.date
                        )
                    }
                }

                for pr in repo.pullRequests {
                    if try insert(pr, projectID: project.id) { inserted += 1 }
                }

                let newest = ([project.lastCommitAt] + repo.commits.map(\.date)).compactMap { $0 }.max()
                try database.updateScan(projectID: project.id, scannedAt: now, lastCommitAt: newest, remote: repo.remote)
            }
            return inserted
        }
    }

    /// PRs de fontes externas (ex: `gh`), ligados ao projeto local pelo remote quando ele existe.
    @discardableResult
    public func importPullRequests(_ pullRequests: [RawPullRequest]) throws -> Int {
        try database.transaction {
            let byRemote = Dictionary(
                try database.projects().compactMap { p in p.remote.map { ($0, p.id) } },
                uniquingKeysWith: { first, _ in first }
            )
            var inserted = 0
            for pr in pullRequests {
                if try insert(pr, projectID: byRemote[pr.repo]) { inserted += 1 }
            }
            return inserted
        }
    }

    private func insert(_ pr: RawPullRequest, projectID: Int64?) throws -> Bool {
        // Sem projeto local, o nome do repositório vai no detalhe para não perder a origem.
        let detail = pr.branches ?? (projectID == nil ? String(pr.repo.split(separator: "/").dropFirst().joined(separator: "/")) : nil)
        let wrote = try database.insertEvent(
            uid: pr.uid, kind: .pullRequest, date: pr.date, title: pr.title, detail: detail,
            author: pr.authorEmail, projectID: projectID, ref: pr.ref, state: pr.state.rawValue, url: pr.url
        )
        // PR com [deploy] no título: um lembrete só, no evento de abertura ou no de merge que chegar primeiro.
        let message = CommitMessage.parse(pr.title)
        if wrote, message.wantsDeploy, let projectID,
           try !database.deployTasks().contains(where: { $0.projectID == projectID && $0.kind == .pullRequest && $0.ref == pr.ref }) {
            try database.insertDeployTask(
                projectID: projectID, kind: .pullRequest, ref: pr.ref, title: message.text, eventUID: pr.uid, createdAt: pr.date
            )
        }
        return wrote
    }
}
