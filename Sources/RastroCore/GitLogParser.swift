import Foundation

public struct RawCommit: Sendable, Equatable {
    public let hash: String
    public let authorName: String
    public let authorEmail: String
    public let date: Date
    public let subject: String

    public init(hash: String, authorName: String, authorEmail: String, date: Date, subject: String) {
        self.hash = hash
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.date = date
        self.subject = subject
    }
}

/// Lê a saída de `git log` no formato definido em `GitLogParser.format`.
public enum GitLogParser {
    static let fieldSeparator: Character = "\u{1F}"
    static let recordSeparator: Character = "\u{1E}"

    /// Hash, nome, email, data ISO 8601 estrita e assunto, separados por US e terminados por RS.
    public static let format = "--pretty=format:%H%x1f%an%x1f%ae%x1f%aI%x1f%s%x1e"

    public static func parse(_ output: String) -> [RawCommit] {
        let dateFormatter = ISO8601DateFormatter()
        return output.split(separator: recordSeparator).compactMap { record in
            let fields = record
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: fieldSeparator, omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count == 5, let date = dateFormatter.date(from: fields[3]) else { return nil }
            return RawCommit(
                hash: fields[0],
                authorName: fields[1],
                authorEmail: fields[2],
                date: date,
                subject: fields[4]
            )
        }
    }

    /// Mantém só commits cujo email bate com algum da lista (sem diferenciar maiúsculas). Lista vazia não filtra.
    public static func filter(_ commits: [RawCommit], authorEmails: [String]) -> [RawCommit] {
        let allowed = Set(authorEmails.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
        guard !allowed.isEmpty else { return commits }
        return commits.filter { allowed.contains($0.authorEmail.lowercased()) }
    }
}
