import RastroCore

extension EventKind {
    var label: String {
        switch self {
        case .commit: "Commits"
        case .pullRequest: "PRs"
        case .deploy: "Deploys"
        case .note: "Notas"
        }
    }

    var symbol: String {
        switch self {
        case .commit: "point.topleft.down.to.point.bottomright.curvepath"
        case .pullRequest: "arrow.triangle.merge"
        case .deploy: "shippingbox"
        case .note: "note.text"
        }
    }
}
