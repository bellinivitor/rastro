import RastroCore
import SwiftUI

/// Criar uma nota nova ou editar uma existente (`note` preenchido).
struct NoteEditorView: View {
    var note: Event?

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var detail = ""
    @State private var date = Date.now
    @State private var projectID: Int64?
    @FocusState private var textFocused: Bool

    /// Título é opcional: basta o texto (ou só o título, para quem prefere).
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty || !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var projects: [Project] {
        store.projects.filter { !$0.isHidden && store.eventCounts[$0.id, default: 0] > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Editor de verdade: a nota pode ser longa e rola por dentro.
            TextEditor(text: $detail)
                .font(.body)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .focused($textFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if detail.isEmpty {
                        Text("O que aconteceu?")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .padding([.horizontal, .top], 20)
                .accessibilityLabel("Nota")

            Form {
                TextField("Título", text: $title, prompt: Text("Opcional"))
                Picker("Projeto", selection: $projectID) {
                    Text("Nenhum").tag(Int64?.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Int64?.some(project.id))
                    }
                }
                DatePicker("Data", selection: $date)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 170)

            HStack {
                if let note {
                    Button("Apagar nota", role: .destructive) {
                        store.delete(note)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(note == nil ? "Adicionar" : "Salvar", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 900, minHeight: 520, idealHeight: 600, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.async { textFocused = true }
            guard let note else { return }
            title = note.title
            detail = note.detail ?? ""
            date = note.date
            projectID = note.projectID
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note {
            store.updateNote(note, title: cleanTitle, detail: cleanDetail.isEmpty ? nil : cleanDetail, date: date, projectID: projectID)
        } else {
            store.addNote(title: cleanTitle, detail: cleanDetail.isEmpty ? nil : cleanDetail, date: date, projectID: projectID)
        }
        dismiss()
    }
}
