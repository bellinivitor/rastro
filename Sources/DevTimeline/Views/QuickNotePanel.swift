import AppKit
import DevTimelineCore
import SwiftUI

/// Janela flutuante da nota rápida (⌥⌘N). Abre sobre qualquer app, inclusive em tela cheia,
/// sem trazer o Dev Timeline para frente: escreveu, Enter, volta ao que estava fazendo.
@MainActor
final class QuickNoteController: NSObject, NSWindowDelegate {
    static let shared = QuickNoteController()

    private var panel: QuickNotePanel?

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        close()
        let panel = QuickNotePanel()
        panel.delegate = self
        let view = QuickNoteView(onClose: { [weak self] in self?.close() })
            .environment(AppStore.shared)
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(panel.contentView!.fittingSize)

        // Terço superior da tela onde está o mouse, como o Spotlight.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + frame.height * 0.66))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Painel que aceita teclado sem ativar o app; Esc fecha.
final class QuickNotePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 140),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? QuickNoteController)?.close()
    }
}

struct QuickNoteView: View {
    let onClose: () -> Void

    @Environment(AppStore.self) private var store
    @AppStorage("quickNote.lastProject") private var lastProjectID = 0

    @State private var text = ""
    @State private var projectID: Int64?
    @FocusState private var titleFocused: Bool

    private var projects: [Project] {
        store.projects
            .filter { !$0.isHidden && store.eventCounts[$0.id, default: 0] > 0 }
            .sorted { ($0.lastCommitAt ?? .distantPast) > ($1.lastCommitAt ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("O que você fez?", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($titleFocused)
                    .onSubmit(save)
            }

            HStack(spacing: 10) {
                Picker("Projeto", selection: $projectID) {
                    Text("Sem projeto").tag(Int64?.none)
                    Divider()
                    ForEach(projects) { project in
                        Text(project.name).tag(Int64?.some(project.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text("Enter salva, Esc fecha")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 30)
        }
        .padding(18)
        .frame(width: 540)
        .background(.regularMaterial)
        .onAppear {
            projectID = projects.first { $0.id == Int64(lastProjectID) }?.id ?? projects.first?.id
            // O foco só pega depois que o painel virou janela-chave.
            DispatchQueue.main.async { titleFocused = true }
        }
    }

    private func save() {
        // Nota rápida não tem título: o texto é a nota.
        let clean = text.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        store.addNote(title: "", detail: clean, date: .now, projectID: projectID)
        lastProjectID = Int(projectID ?? 0)
        onClose()
    }
}
