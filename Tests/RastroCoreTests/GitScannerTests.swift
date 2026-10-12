import Foundation
import Testing
@testable import RastroCore

/// Cria repositórios git reais numa pasta temporária.
struct GitScannerTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("rastro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func git(_ args: String..., in dir: URL, date: String? = nil) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        if let date { env["GIT_AUTHOR_DATE"] = date; env["GIT_COMMITTER_DATE"] = date }
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    func makeRepo(_ relative: String, commits: [(email: String, subject: String, date: String)]) throws -> URL {
        let dir = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try git("init", "-q", in: dir)
        for commit in commits {
            try git("-c", "user.name=Teste", "-c", "user.email=\(commit.email)",
                    "commit", "-q", "--allow-empty", "-m", commit.subject, in: dir, date: commit.date)
        }
        return dir
    }

    @Test func findsReposWithoutDescendingIntoThem() throws {
        let api = try makeRepo("cliente/api", commits: [])
        try makeRepo("cliente/api/nested", commits: [])
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules/lib/.git"), withIntermediateDirectories: true)
        let found = RepoFinder.find(in: root).map(\.lastPathComponent)
        #expect(found == [api.lastPathComponent])
    }

    @Test func scansAndFiltersByAuthor() throws {
        let repo = try makeRepo("site", commits: [
            ("eu@x.com", "feat: um", "2026-10-01T10:00:00Z"),
            ("outro@x.com", "feat: dois", "2026-10-02T10:00:00Z"),
            ("eu@x.com", "fix: três", "2026-10-03T10:00:00Z"),
        ])
        try makeRepo("vazio", commits: [])

        let repos = GitScanner.scan(root: root, authorEmails: ["eu@x.com"], since: [:])
        #expect(repos.map(\.name) == ["site", "vazio"])
        #expect(repos[0].path == RepoFinder.canonical(repo).path)
        #expect(repos[0].commits.map(\.subject).sorted() == ["feat: um", "fix: três"])
        #expect(repos[1].commits.isEmpty)
    }

    @Test func incrementalScanUsesSince() throws {
        let repo = try makeRepo("app", commits: [
            ("eu@x.com", "antigo", "2026-01-01T10:00:00Z"),
            ("eu@x.com", "novo", "2026-10-01T10:00:00Z"),
        ])
        let since = [RepoFinder.canonical(repo).path: ISO8601DateFormatter().date(from: "2026-09-30T00:00:00Z")!]
        let repos = GitScanner.scan(root: root, authorEmails: [], since: since)
        #expect(repos.first?.commits.map(\.subject) == ["novo"])
    }

    @Test func readsCommitBody() throws {
        let repo = try makeRepo("corpo", commits: [])
        try git("-c", "user.name=T", "-c", "user.email=eu@x.com", "commit", "-q", "--allow-empty",
                "-m", "feat: título", "-m", "Primeira linha do corpo.\n\nSegundo parágrafo.", in: repo)
        try git("-c", "user.name=T", "-c", "user.email=eu@x.com", "commit", "-q", "--allow-empty", "-m", "sem corpo", in: repo)
        let commits = GitScanner.scan(root: root, authorEmails: [], since: [:]).first { $0.name == "corpo" }!.commits
        let withBody = try #require(commits.first { $0.subject == "feat: título" })
        let without = try #require(commits.first { $0.subject == "sem corpo" })
        let path = RepoFinder.canonical(repo).path
        #expect(GitScanner.commitBody(repoPath: path, hash: withBody.hash) == "Primeira linha do corpo.\n\nSegundo parágrafo.")
        #expect(GitScanner.commitBody(repoPath: path, hash: without.hash) == "")
        #expect(GitScanner.commitBody(repoPath: path, hash: "naoexiste") == nil)
    }

    @Test func multipleRootsDeduplicateNestedFolders() throws {
        let api = try makeRepo("cliente/api", commits: [("eu@x.com", "feat: um", "2026-10-01T10:00:00Z")])
        try makeRepo("outro/site", commits: [])
        let repos = GitScanner.scan(
            roots: [root, root.appendingPathComponent("cliente"), root.appendingPathComponent("outro")],
            authorEmails: [], since: [:]
        )
        #expect(repos.map(\.name).sorted() == ["api", "site"])
        #expect(repos.first { $0.name == "api" }?.path == RepoFinder.canonical(api).path)
    }
}
