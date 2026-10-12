import RastroCore
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(AppSettings.authorEmailsKey) private var authorEmails = ""

    @State private var selection: SidebarItem?
    @State private var isAddingNote = false
    @State private var isShowingStandup: Bool

    /// `screen` escolhe a tela inicial (usado pelo modo demonstração e pelos prints).
    init(screen: String? = DemoMode.screen) {
        let initial: SidebarItem = switch screen {
        case "stats": .stats
        case "deploy": .deploys
        default: .timeline
        }
        _selection = State(initialValue: initial)
        _isShowingStandup = State(initialValue: screen == "standup")
    }

    var body: some View {
        container
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isShowingStandup.toggle()
                } label: {
                    Label("Standup", systemImage: "text.bubble")
                }
                .keyboardShortcut("u")
                .help("Montar o standup (⌘U)")

                Button {
                    isAddingNote = true
                } label: {
                    Label("Nova nota", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n")

                Button {
                    Task { await store.scan() }
                } label: {
                    if store.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Escanear", systemImage: "arrow.clockwise")
                    }
                }
                .keyboardShortcut("r")
                .disabled(store.isScanning)
            }
        }
        .sheet(isPresented: $isShowingStandup) {
            StandupView()
        }
        .sheet(isPresented: $isAddingNote) {
            NoteEditorView()
        }
        .task {
            if !DemoMode.isOn, authorEmails.isEmpty, let email = GitScanner.globalUserEmail(), !email.isEmpty {
                authorEmails = email
            }
        }
    }

    /// Nos prints (`--snapshot`), barra lateral e conteúdo lado a lado num contêiner simples:
    /// a coluna lateral do NavigationSplitView depende da composição do servidor de janelas
    /// e não é desenhada fora da tela. Fora dos prints, o NavigationSplitView de sempre.
    @ViewBuilder
    private var container: some View {
        if Snapshots.isActive {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 240)
                    .background(Color(white: 0.165))
                Divider()
                NavigationStack { detail }
            }
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
        }
    }

    private var sidebar: some View {
            SidebarView(selection: $selection)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if store.status != nil || store.shortcutWarning != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        if let warning = store.shortcutWarning {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        if let status = store.status {
                            Text(status).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)
                    .overlay(alignment: .top) { Divider() }
                }
            }
    }

    @ViewBuilder
    private var detail: some View {
            switch selection {
            case .stats:
                StatsView()
            case .deploys:
                DeployView()
            case .group(let id):
                TimelineView(
                    projectIDs: Set(store.projects.filter { $0.groupID == id }.map(\.id)),
                    title: store.groups.first { $0.id == id }?.name ?? "Grupo"
                )
            case .project(let id), .favorite(let id):
                TimelineView(projectIDs: [id], title: store.projectsByID[id]?.name ?? "Projeto")
            case .timeline, nil:
                TimelineView(projectIDs: nil)
            }
    }
}
