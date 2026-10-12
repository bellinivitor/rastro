import Foundation

public struct Project: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var path: String
    public var name: String
    public var colorHex: String
    public var lastScannedAt: Date?
    public var lastCommitAt: Date?
    /// Remote `origin` normalizado (ex: `github.com/dono/repo`), para ligar PRs do GitHub ao projeto local.
    public var remote: String?
    /// Destacado no topo da barra lateral.
    public var isFavorite: Bool
    /// Fora da barra lateral, da timeline, do standup e das estatísticas.
    public var isHidden: Bool
    /// Grupo (cliente) a que o projeto pertence.
    public var groupID: Int64?

    public init(
        id: Int64, path: String, name: String, colorHex: String, lastScannedAt: Date? = nil, lastCommitAt: Date? = nil,
        remote: String? = nil, isFavorite: Bool = false, isHidden: Bool = false, groupID: Int64? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.colorHex = colorHex
        self.lastScannedAt = lastScannedAt
        self.lastCommitAt = lastCommitAt
        self.remote = remote
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.groupID = groupID
    }
}

/// Grupo de projetos, normalmente um cliente (ex: um cliente).
public struct ProjectGroup: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }
}

/// Conjunto de commits/PRs de um projeto que sobem juntos.
public struct Epic: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var projectID: Int64
    public var name: String
    public var createdAt: Date

    public init(id: Int64, projectID: Int64, name: String, createdAt: Date) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.createdAt = createdAt
    }
}

public enum EventKind: String, CaseIterable, Identifiable, Sendable {
    case commit
    case pullRequest
    case deploy
    case note

    public var id: String { rawValue }
}

public struct Event: Identifiable, Hashable, Sendable {
    public let id: Int64
    /// Chave de deduplicação: `commit:<repo>#<hash>`, `pr:<remote>#<n>:<estado>`, `deploy:<id da pendência>` ou `note:<uuid>`.
    public var uid: String
    public var kind: EventKind
    public var date: Date
    public var title: String
    public var detail: String?
    public var author: String?
    public var projectID: Int64?
    /// Referência exibida do PR/MR: `#72` (GitHub) ou `!66` (GitLab).
    public var ref: String?
    /// Estado do PR/MR no momento do evento: `open`, `merged` ou `closed`.
    public var state: String?
    public var url: String?

    public init(id: Int64, uid: String, kind: EventKind, date: Date, title: String, detail: String? = nil, author: String? = nil, projectID: Int64? = nil, ref: String? = nil, state: String? = nil, url: String? = nil) {
        self.id = id
        self.uid = uid
        self.kind = kind
        self.date = date
        self.title = title
        self.detail = detail
        self.author = author
        self.projectID = projectID
        self.ref = ref
        self.state = state
        self.url = url
    }
}

extension Event {
    /// O que mostrar como linha principal: o título, ou, em nota sem título, a primeira linha do texto.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return detail?.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// Hash do commit, tirado do uid `commit:<repo>#<hash>`.
    public var commitHash: String? {
        guard kind == .commit, uid.hasPrefix("commit:"), let hash = uid.split(separator: "#").last, !hash.isEmpty else { return nil }
        return String(hash)
    }
}
