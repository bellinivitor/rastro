import Foundation

/// Separa o tipo de um commit (`feat`, `fix`…) do texto, aceitando os estilos
/// `feat: x`, `FEAT(api)!: x`, `[BUGFIX] x` e `[fix]: x`.
/// A marca `[deploy]` ou `#deploy` em qualquer posição pede um lembrete de deploy e sai do texto.
public struct CommitMessage: Equatable, Sendable {
    public let type: String?
    public let text: String
    public let wantsDeploy: Bool

    static let knownTypes: [String: String] = [
        "feat": "feat", "feature": "feat",
        "fix": "fix", "bugfix": "fix", "hotfix": "fix",
        "refactor": "refactor", "chore": "chore", "docs": "docs",
        "test": "test", "tests": "test", "style": "style", "perf": "perf",
        "build": "build", "ci": "ci", "revert": "revert", "wip": "wip",
    ]

    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(?:\[(\w+)\]|(\w+)(?:\([^)]*\))?!?\s*:)\s*:?\s*"#
    )

    public init(type: String?, text: String, wantsDeploy: Bool = false) {
        self.type = type
        self.text = text
        self.wantsDeploy = wantsDeploy
    }

    private static let deployTag = try! NSRegularExpression(
        pattern: #"\s*(?:\[deploy\]|#deploy\b)\s*"#, options: [.caseInsensitive]
    )

    /// Primeiro item quando a mensagem junta vários com " - " (ex: "Ajusta X - Corrige Y").
    public var headline: String {
        text.range(of: " - ").map { String(text[..<$0.lowerBound]) } ?? text
    }

    /// Os itens seguintes, se houver.
    public var details: [String] {
        text.components(separatedBy: " - ").dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func parse(_ original: String) -> CommitMessage {
        let fullRange = NSRange(original.startIndex..., in: original)
        let wantsDeploy = deployTag.firstMatch(in: original, range: fullRange) != nil
        let subject = wantsDeploy
            ? deployTag.stringByReplacingMatches(in: original, range: fullRange, withTemplate: " ")
                .trimmingCharacters(in: .whitespaces)
            : original
        let parsed = parseType(subject)
        return CommitMessage(type: parsed.type, text: parsed.text, wantsDeploy: wantsDeploy)
    }

    private static func parseType(_ subject: String) -> CommitMessage {
        let range = NSRange(subject.startIndex..., in: subject)
        guard let match = pattern.firstMatch(in: subject, range: range) else {
            return CommitMessage(type: nil, text: subject)
        }
        let captured = [1, 2]
            .compactMap { Range(match.range(at: $0), in: subject) }
            .map { subject[$0].lowercased() }
            .first
        guard let raw = captured, let type = knownTypes[raw] else {
            return CommitMessage(type: nil, text: subject)
        }
        let rest = String(subject[Range(match.range, in: subject)!.upperBound...])
        guard !rest.isEmpty else { return CommitMessage(type: nil, text: subject) }
        return CommitMessage(type: type, text: rest.prefix(1).uppercased() + rest.dropFirst())
    }
}
