import RastroCore
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(AppSettings.authorEmailsKey) private var authorEmails = ""

    @State private var selection: SidebarItem? = .timeline
    @State private var isAddingNote = false
    @State private var isShowingStandup = false

    var body: some View {
        NavigationSplitView {
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
        } detail: {
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
            if authorEmails.isEmpty, let email = GitScanner.globalUserEmail(), !email.isEmpty {
                authorEmails = email
            }
        }
    }
}
