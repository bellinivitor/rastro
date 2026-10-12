import Foundation

/// Um evento de PR/MR: aberto, mergeado ou fechado. Vem dos merges locais ou do `gh`.
public struct RawPullRequest: Sendable, Equatable {
    public enum State: String, Sendable {
        case open, merged, closed
    }

    /// Remote normalizado (`github.com/dono/repo`, `gitlab.empresa.com/grupo/projeto`) ou `local:<caminho>`.
    public let repo: String
    public let number: Int
    public let title: String
    public let state: State
    /// Quando o evento aconteceu: abertura ou merge/fechamento.
    public let date: Date
    /// Ex: `develop → desenv`, quando o merge local informa.
    public let branches: String?
    public let url: String?
    /// Quem fez o merge (merges locais); nil quando vem do `gh` (já filtrado por @me).
    public let authorEmail: String?

    public init(repo: String, number: Int, title: String, state: State, date: Date, branches: String? = nil, url: String? = nil, authorEmail: String? = nil) {
        self.repo = repo
        self.number = number
        self.title = title
        self.state = state
        self.date = date
        self.branches = branches
        self.url = url
        self.authorEmail = authorEmail
    }

    public var isGitHub: Bool { repo.hasPrefix("github.com/") }
    /// `#72` no GitHub, `!66` no GitLab.
    public var ref: String { (isGitHub ? "#" : "!") + String(number) }
    /// Um evento por estado: abrir e mergear o mesmo PR são dois eventos.
    public var uid: String { "pr:\(repo)#\(number):\(state.rawValue)" }
}

public enum RemoteURL {
    /// `git@github.com:Dono/Repo.git`, `https://user@host/a/b.git`, `ssh://git@host:22/a/b` → `host/caminho` em minúsculas.
    public static func normalize(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let scheme = text.range(of: "://") {
            text = String(text[scheme.upperBound...])
            if let at = text.firstIndex(of: "@"), at < (text.firstIndex(of: "/") ?? text.endIndex) {
                text = String(text[text.index(after: at)...])
            }
            // Remove porta: host:22/caminho
            if let colon = text.firstIndex(of: ":"), let slash = text.firstIndex(of: "/"), colon < slash {
                text = String(text[..<colon]) + String(text[slash...])
            }
        } else if let at = text.firstIndex(of: "@"), let colon = text.firstIndex(of: ":"), at < colon {
            // Formato scp: git@host:dono/repo
            text = String(text[text.index(after: at)..<colon]) + "/" + String(text[text.index(after: colon)...])
        } else {
            return nil
        }
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix(".git") { text.removeLast(4) }
        return text.contains("/") ? text.lowercased() : nil
    }

    public static func webURL(repo: String, number: Int) -> String? {
        guard !repo.hasPrefix("local:") else { return nil }
        return repo.hasPrefix("github.com/")
            ? "https://\(repo)/pull/\(number)"
            : "https://\(repo)/-/merge_requests/\(number)"
    }

    static func host(_ remote: String) -> String {
        String(remote.prefix { $0 != "/" })
    }
}

/// Reconhece PRs/MRs nos commits de merge que o GitHub e o GitLab gravam no repositório.
public enum MergeParser {
    public static let format = "--pretty=format:%H%x1f%an%x1f%ae%x1f%aI%x1f%B%x1e"

    private static let gitHubSubject = try! NSRegularExpression(pattern: #"^Merge pull request #(\d+) from \S+"#)
    private static let gitLabReference = try! NSRegularExpression(pattern: #"See merge request (\S+)!(\d+)"#)
    private static let gitLabSubject = try! NSRegularExpression(pattern: #"^Merge branch '(.+)' into '(.+)'"#)

    public static func parse(_ output: String, repoPath: String, remote: String?) -> [RawPullRequest] {
        let dateFormatter = ISO8601DateFormatter()
        return output.split(separator: "\u{1E}").compactMap { record in
            let fields = record
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\u{1F}", maxSplits: 4, omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count == 5, let date = dateFormatter.date(from: fields[3]) else { return nil }
            return parseMessage(fields[4], date: date, authorEmail: fields[2], repoPath: repoPath, remote: remote)
        }
    }

    static func parseMessage(_ message: String, date: Date, authorEmail: String, repoPath: String, remote: String?) -> RawPullRequest? {
        let lines = message.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let subject = lines.first else { return nil }
        let body = lines.dropFirst().filter { !$0.isEmpty }

        if let match = first(gitHubSubject, in: subject), let number = Int(match[1]) {
            let repo = remote ?? "local:\(repoPath)"
            return RawPullRequest(
                repo: repo, number: number, title: body.first ?? subject, state: .merged, date: date,
                url: RemoteURL.webURL(repo: repo, number: number), authorEmail: authorEmail
            )
        }

        if let reference = lines.lazy.compactMap({ first(gitLabReference, in: $0) }).first, let number = Int(reference[2]) {
            let repo = remote.map { "\(RemoteURL.host($0))/\(reference[1].lowercased())" } ?? "local:\(repoPath)"
            let title = body.first { !$0.hasPrefix("See merge request") } ?? subject
            let branches = first(gitLabSubject, in: subject).map { "\($0[1]) → \($0[2])" }
            return RawPullRequest(
                repo: repo, number: number, title: title, state: .merged, date: date, branches: branches,
                url: RemoteURL.webURL(repo: repo, number: number), authorEmail: authorEmail
            )
        }
        return nil
    }

    private static func first(_ regex: NSRegularExpression, in text: String) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

/// PRs do GitHub pelo `gh` já autenticado na máquina (sem guardar token no app).
public enum GitHubCLI {
    static let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    public static var executable: String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// PRs de autoria sua atualizados desde `since`: um evento ao abrir e outro ao mergear/fechar.
    public static func fetch(since: Date) throws -> [RawPullRequest] {
        guard let gh = executable else { throw Failure(description: "gh não encontrado") }
        let day = since.formatted(.iso8601.year().month().day())
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = [
            "search", "prs", "--author=@me", "--updated=>=\(day)", "--limit", "300",
            "--json", "number,title,state,url,repository,createdAt,closedAt",
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errorData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(description: message.isEmpty ? "gh terminou com erro \(process.terminationStatus)" : message)
        }
        return try parse(data)
    }

    struct Item: Decodable {
        struct Repository: Decodable { let nameWithOwner: String }
        let number: Int
        let title: String
        let state: String
        let url: String
        let repository: Repository
        let createdAt: Date
        let closedAt: Date
    }

    public static func parse(_ data: Data) throws -> [RawPullRequest] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // O gh usa 0001-01-01 como "nunca fechado".
        let never = Date(timeIntervalSince1970: 0)

        return try decoder.decode([Item].self, from: data).flatMap { item -> [RawPullRequest] in
            let repo = "github.com/\(item.repository.nameWithOwner.lowercased())"
            var events = [RawPullRequest(repo: repo, number: item.number, title: item.title, state: .open, date: item.createdAt, url: item.url)]
            if item.closedAt > never, let state = RawPullRequest.State(rawValue: item.state.lowercased()), state != .open {
                events.append(RawPullRequest(repo: repo, number: item.number, title: item.title, state: state, date: item.closedAt, url: item.url))
            }
            return events
        }
    }
}
