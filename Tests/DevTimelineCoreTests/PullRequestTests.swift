import Foundation
import Testing
@testable import DevTimelineCore

struct RemoteURLTests {
    @Test(arguments: [
        ("git@github.com:Acme/Loja-API.git", "github.com/acme/loja-api"),
        ("https://github.com/acme/loja-api.git", "github.com/acme/loja-api"),
        ("https://gitlab.empresa.com.br/time/projeto/frontend.git", "gitlab.empresa.com.br/time/projeto/frontend"),
        ("https://dev@gitlab.empresa.com/grupo/app", "gitlab.empresa.com/grupo/app"),
        ("ssh://git@gitlab.empresa.com:2222/grupo/app.git/", "gitlab.empresa.com/grupo/app"),
    ])
    func normalizes(raw: String, expected: String) {
        #expect(RemoteURL.normalize(raw) == expected)
    }

    @Test func rejectsLocalPathsAndEmpty() {
        #expect(RemoteURL.normalize("/Users/eu/repo") == nil)
        #expect(RemoteURL.normalize("") == nil)
        #expect(RemoteURL.normalize(nil) == nil)
    }
}

struct MergeParserTests {
    let date = "2026-10-10T15:00:00-03:00"

    func record(_ email: String, _ message: String) -> String {
        "abc\u{1F}Dev\u{1F}\(email)\u{1F}\(date)\u{1F}\(message)\u{1E}"
    }

    @Test func parsesGitLabMergeRequest() throws {
        let output = record("eu@x.com", """
        Merge branch 'fix/OS-000-HUXXX' into 'develop'

        [BUGFIX] Correção prévia - Painéis de Análise

        See merge request time/projeto/frontend!65
        """)
        let pr = try #require(MergeParser.parse(output, repoPath: "/r/front", remote: "gitlab.empresa.com.br/time/projeto/frontend").first)
        #expect(pr.repo == "gitlab.empresa.com.br/time/projeto/frontend")
        #expect(pr.number == 65)
        #expect(pr.ref == "!65")
        #expect(pr.title == "[BUGFIX] Correção prévia - Painéis de Análise")
        #expect(pr.branches == "fix/OS-000-HUXXX → develop")
        #expect(pr.state == .merged)
        #expect(pr.authorEmail == "eu@x.com")
        #expect(pr.url == "https://gitlab.empresa.com.br/time/projeto/frontend/-/merge_requests/65")
        #expect(pr.uid == "pr:gitlab.empresa.com.br/time/projeto/frontend#65:merged")
    }

    @Test func gitLabWithoutTitleFallsBackToSubject() throws {
        let output = record("eu@x.com", "Merge branch 'a' into 'b'\n\nSee merge request g/p!3")
        let pr = try #require(MergeParser.parse(output, repoPath: "/r/p", remote: nil).first)
        #expect(pr.title == "Merge branch 'a' into 'b'")
        #expect(pr.repo == "local:/r/p")
        #expect(pr.url == nil)
    }

    @Test func parsesGitHubPullRequest() throws {
        let output = record("eu@x.com", "Merge pull request #72 from dev/feat-frete\n\nFEAT: Ajustar transportadora default")
        let pr = try #require(MergeParser.parse(output, repoPath: "/r/t", remote: "github.com/acme/loja-api").first)
        #expect(pr.ref == "#72")
        #expect(pr.title == "FEAT: Ajustar transportadora default")
        #expect(pr.url == "https://github.com/acme/loja-api/pull/72")
    }

    @Test func ignoresPlainMerges() {
        let output = record("eu@x.com", "Merge remote-tracking branch 'origin/dev' into dev")
            + record("eu@x.com", "Merge branch 'feat/x' into develop")
        #expect(MergeParser.parse(output, repoPath: "/r", remote: "github.com/a/b").isEmpty)
    }
}

struct GitHubCLITests {
    @Test func parsesOpenAndMergedPullRequests() throws {
        let json = """
        [{"closedAt":"0001-01-01T00:00:00Z","createdAt":"2026-09-28T13:37:32Z","number":60,
          "repository":{"nameWithOwner":"Acme/loja-web"},"state":"open",
          "title":"FEAT: Ajustar status","url":"https://github.com/Acme/loja-web/pull/60"},
         {"closedAt":"2026-09-24T18:13:56Z","createdAt":"2026-09-18T14:25:46Z","number":81,
          "repository":{"nameWithOwner":"Acme/loja-api"},"state":"merged",
          "title":"FEAT: Gerar relatório mensal","url":"https://github.com/Acme/loja-api/pull/81"}]
        """
        let prs = try GitHubCLI.parse(Data(json.utf8))
        #expect(prs.map(\.uid) == [
            "pr:github.com/acme/loja-web#60:open",
            "pr:github.com/acme/loja-api#81:open",
            "pr:github.com/acme/loja-api#81:merged",
        ])
        #expect(prs[2].date == ISO8601DateFormatter().date(from: "2026-09-24T18:13:56Z"))
        #expect(prs[2].ref == "#81")
    }
}

struct PullRequestImportTests {
    @Test func localMergeAndGitHubDeduplicateAndLinkByRemote() throws {
        let db = try Database(path: ":memory:")
        let importer = Importer(database: db, palette: [])
        let merged = RawPullRequest(
            repo: "github.com/acme/loja-api", number: 81, title: "FEAT: Gerar relatório", state: .merged,
            date: ISO8601DateFormatter().date(from: "2026-09-24T18:13:56Z")!, authorEmail: "eu@x.com"
        )
        try importer.importRepos([ScannedRepo(path: "/r/tc", name: "loja-api", commits: [], remote: "github.com/acme/loja-api", pullRequests: [merged])])

        let fromGitHub = [
            RawPullRequest(repo: merged.repo, number: 81, title: merged.title, state: .open, date: .now),
            merged,
            RawPullRequest(repo: "github.com/outro/repo", number: 5, title: "Sem projeto", state: .open, date: .now),
        ]
        #expect(try importer.importPullRequests(fromGitHub) == 2)

        let project = try #require(db.projects().first)
        #expect(project.remote == "github.com/acme/loja-api")
        let events = try db.events()
        #expect(events.count == 3)
        #expect(events.filter { $0.projectID == project.id }.compactMap(\.state).sorted() == ["merged", "open"])
        let orphan = try #require(events.first { $0.projectID == nil })
        #expect(orphan.detail == "outro/repo")
        #expect(orphan.kind == .pullRequest)
        #expect(orphan.ref == "#5")
    }
}
