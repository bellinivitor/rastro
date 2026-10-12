import Foundation

/// Lembrete de "isso precisa ir para produção" num projeto.
public struct DeployTask: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case commit, pullRequest, branch, text
        /// A epic inteira; `ref` guarda o id da epic.
        case epic
    }

    public let id: Int64
    public var projectID: Int64
    public var kind: Kind
    /// Hash do commit, referência do PR (`#72`, `!66`) ou nome da branch.
    public var ref: String?
    public var title: String
    /// Evento da timeline que originou o lembrete, quando houver.
    public var eventUID: String?
    public var createdAt: Date
    public var doneAt: Date?

    public init(id: Int64, projectID: Int64, kind: Kind, ref: String?, title: String, eventUID: String?, createdAt: Date, doneAt: Date? = nil) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.ref = ref
        self.title = title
        self.eventUID = eventUID
        self.createdAt = createdAt
        self.doneAt = doneAt
    }

    public var isPending: Bool { doneAt == nil }

    /// Lembrete a partir de um commit ou PR da timeline.
    public static func draft(from event: Event) -> (kind: Kind, ref: String?, title: String)? {
        switch event.kind {
        case .commit:
            return (.commit, event.commitHash, CommitMessage.parse(event.title).headline)
        case .pullRequest:
            return (.pullRequest, event.ref, CommitMessage.parse(event.title).text)
        case .note, .deploy:
            return nil
        }
    }
}
