import SwiftUI

/// Lista de tarefas curta, guardada como texto (um item por linha).
/// Itens numa caixa, com um campo "Adicionar…" no fim: Enter adiciona e limpa o campo.
struct EditableList: View {
    struct Suggestion: Hashable {
        /// O que entra na lista ao clicar.
        let text: String
        /// Referência curta (ex: "PR #60"), título e projeto, para mostrar.
        let label: String
        let title: String
        let project: String?
    }

    @Binding var text: String
    let addPrompt: String
    var suggestions: [Suggestion] = []

    @State private var draft = ""
    @FocusState private var isAdding: Bool

    private var items: [String] {
        text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    ItemRow(text: item) { update(index, to: $0) } onDelete: { remove(index) }
                    Divider().padding(.leading, 32)
                }
                addRow
            }
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(isAdding ? 0.25 : 0.08)))

            let available = suggestions.filter { !items.contains($0.text) }
            if !available.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Em aberto").font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                    ForEach(available, id: \.self) { suggestion in
                        SuggestionRow(suggestion: suggestion) { append(suggestion.text) }
                    }
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.callout.weight(.semibold))
                .foregroundStyle(isAdding ? Color.accentColor : .secondary)
                .frame(width: 14)
            TextField(addPrompt, text: $draft)
                .textFieldStyle(.plain)
                .focused($isAdding)
                .onSubmit {
                    append(draft)
                    draft = ""
                    isAdding = true
                }
            if !draft.isEmpty {
                Text("Enter").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { isAdding = true }
    }

    // MARK: Edição

    private func save(_ list: [String]) {
        text = list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func append(_ item: String) {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        save(items + [trimmed])
    }

    private func update(_ index: Int, to value: String) {
        var list = items
        guard list.indices.contains(index) else { return }
        list[index] = value
        save(list)
    }

    private func remove(_ index: Int) {
        var list = items
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        save(list)
    }
}

/// Item já adicionado: editável no lugar; apagar o texto todo e dar Enter remove.
private struct ItemRow: View {
    let text: String
    let onChange: (String) -> Void
    let onDelete: () -> Void

    @State private var editing: String
    @State private var isHovering = false

    init(text: String, onChange: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.text = text
        self.onChange = onChange
        self.onDelete = onDelete
        _editing = State(initialValue: text)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.secondary).frame(width: 5, height: 5).frame(width: 14)
            TextField("Item", text: $editing)
                .textFieldStyle(.plain)
                .onSubmit(commit)
                .onChange(of: text) { editing = text }
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isHovering ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)
            .help("Apagar")
            .accessibilityLabel("Apagar \(text)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onHover { isHovering = $0 }
        // Salva ao sair do campo também, não só no Enter.
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard editing != text else { return }
        if editing.trimmingCharacters(in: .whitespaces).isEmpty { onDelete() } else { onChange(editing) }
    }
}

private struct SuggestionRow: View {
    let suggestion: EditableList.Suggestion
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(isHovering ? Color.accentColor : .secondary)
                Text(suggestion.label).fontWeight(.medium)
                Text(suggestion.title).lineLimit(1)
                Spacer(minLength: 8)
                if let project = suggestion.project {
                    Text(project).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .font(.callout)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Adicionar a Hoje vou")
    }
}
