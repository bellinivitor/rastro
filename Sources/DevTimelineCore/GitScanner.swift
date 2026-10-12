import Foundation

public struct ScannedRepo: Sendable {
    public let path: String
    public let name: String
    public let commits: [RawCommit]
    public var remote: String? = nil
    /// PRs/MRs mergeados por você, reconhecidos nos commits de merge.
    public var pullRequests: [RawPullRequest] = []
}

/// Encontra repositórios e lê os commits de cada um. Síncrono: chame fora da main thread.
public enum GitScanner {
    static let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    /// - Parameter since: data a partir da qual buscar commits, por caminho do repositório (importação incremental).
    public static func scan(root: URL, authorEmails: [String], since: [String: Date]) -> [ScannedRepo] {
        scan(roots: [root], authorEmails: authorEmails, since: since)
    }

    /// Várias pastas raiz; um repositório alcançável por mais de uma (pastas aninhadas) entra uma vez só.
    public static func scan(roots: [URL], authorEmails: [String], since: [String: Date]) -> [ScannedRepo] {
        var seen = Set<String>()
        let repos = roots.flatMap { RepoFinder.find(in: $0) }.filter { seen.insert($0.path).inserted }
        return repos.map { repo in
            var sinceArgs: [String] = []
            if let date = since[repo.path] {
                // Margem de um dia; a deduplicação por uid descarta o que já existe.
                let from = date.addingTimeInterval(-86_400)
                sinceArgs.append("--since=\(ISO8601DateFormatter().string(from: from))")
            }
            let output = run(["log", "--all", "--no-merges", GitLogParser.format] + sinceArgs, in: repo.path) ?? ""
            let commits = GitLogParser.filter(GitLogParser.parse(output), authorEmails: authorEmails)

            let remote = RemoteURL.normalize(run(["remote", "get-url", "origin"], in: repo.path))
            let merges = run(["log", "--all", "--merges", MergeParser.format] + sinceArgs, in: repo.path) ?? ""
            let allowed = Set(authorEmails.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
            let pullRequests = MergeParser.parse(merges, repoPath: repo.path, remote: remote).filter { pr in
                allowed.isEmpty || allowed.contains(pr.authorEmail?.lowercased() ?? "")
            }
            return ScannedRepo(
                path: repo.path, name: repo.lastPathComponent, commits: commits, remote: remote,
                pullRequests: pullRequests
            )
        }
    }

    /// Corpo da mensagem do commit (sem o título), lido na hora. Síncrono: chame fora da main thread.
    public static func commitBody(repoPath: String, hash: String) -> String? {
        run(["show", "-s", "--format=%b", hash], in: repoPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func globalUserEmail() -> String? {
        run(["config", "--global", "user.email"], in: NSHomeDirectory())?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func run(_ args: [String], in dir: String) -> String? {
        let process = Process()
        process.executableURL = gitURL
        process.arguments = ["-C", dir] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // Repositório sem commits sai com erro; tratamos como vazio.
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
