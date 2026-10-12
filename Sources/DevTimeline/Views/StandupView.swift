import AppKit
import DevTimelineCore
import SwiftUI

/// Standup em três partes (o que fiz, o que vou fazer, bloqueios), pronto para colar no chat do time.
struct StandupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var days: [Date] = []
    @State private var day: Date?
    @State private var sections: [StandupSection] = []
    @State private var edits: [String: String] = [:]
    @State private var copied = false

    // Rascunho do dia: sobrevive a fechar a janela, some no dia seguinte.
    @AppStorage("standup.draftDay") private var draftDay = ""
    @AppStorage("standup.plans") private var plans = ""
    @AppStorage("standup.blockers") private var blockers = ""

    private var rendered: Standup.Rendered {
        Standup.render(sections, edits: edits, extras: [("Hoje vou", plans), ("Bloqueios", blockers)])
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if sections.isEmpty {
                        Text("Nenhum commit ou nota nesse dia. Escolha outro dia acima ou escreva só os planos.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                    listSection(title: "Hoje vou") {
                        EditableList(text: $plans, addPrompt: "Adicionar o que você vai fazer hoje", suggestions: planSuggestions)
                    }
                    listSection(title: "Bloqueios") {
                        EditableList(text: $blockers, addPrompt: "Adicionar um bloqueio (ou deixe vazio)")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        // Cabe na janela no tamanho mínimo (600 pt); a lista rola por dentro.
        .frame(width: 560)
        .frame(minHeight: 380, idealHeight: 540)
        .onAppear(perform: load)
        .onChange(of: day) { rebuild() }
        .onChange(of: rendered.plain) { copied = false }
    }

    // MARK: Partes

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Standup").font(.title2.weight(.semibold))
            if !days.isEmpty {
                HStack(spacing: 6) {
                    Text("Desde").foregroundStyle(.secondary)
                    ForEach(days, id: \.self) { candidate in
                        DayChip(title: chipTitle(candidate), isSelected: candidate == day) { day = candidate }
                    }
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionView(_ section: StandupSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title).font(.headline)
            ForEach(section.groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(group.projectID.flatMap { store.projectsByID[$0] }.map { Palette.project($0.colorHex) } ?? .secondary)
                            .frame(width: 8, height: 8)
                        Text(group.project).font(.callout.weight(.medium))
                    }
                    ForEach(group.items) { item in
                        ItemRow(text: binding(for: item))
                    }
                }
            }
        }
    }

    private func listSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    /// O que o app já sabe que está em aberto: deploys pendentes e PRs abertos recentes.
    private var planSuggestions: [EditableList.Suggestion] {
        let deploys = store.pendingDeploys.prefix(3).map { task in
            EditableList.Suggestion(
                text: "Deploy: \(task.title)", label: "Deploy", title: task.title,
                project: store.projectsByID[task.projectID]?.name
            )
        }
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: .now)!
        let closed = Set(store.events.filter { $0.kind == .pullRequest && $0.state != "open" }.map { "\($0.projectID ?? 0)\($0.ref ?? "")" })
        let openPRs = store.events
            .filter { $0.kind == .pullRequest && $0.state == "open" && $0.date >= twoWeeksAgo }
            .filter { !closed.contains("\($0.projectID ?? 0)\($0.ref ?? "")") }
            .prefix(3)
            .map { event in
                let noun = event.ref?.hasPrefix("!") == true ? "MR" : "PR"
                let label = "\(noun) \(event.ref ?? "")"
                let title = CommitMessage.parse(event.title).text
                return EditableList.Suggestion(
                    text: "Acompanhar \(label): \(title)", label: label, title: title,
                    project: store.project(for: event)?.name ?? event.detail
                )
            }
        return Array(deploys) + Array(openPRs)
    }

    private var footer: some View {
        HStack {
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Fechar") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(action: copy) {
                Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var summary: String {
        let items = rendered.itemCount == 1 ? "1 item" : "\(rendered.itemCount) itens"
        let projects = rendered.projectCount == 1 ? "1 projeto" : "\(rendered.projectCount) projetos"
        return rendered.itemCount == 0 ? "Nada para copiar ainda" : "\(items) de \(projects)"
    }

    // MARK: Estado

    private func load() {
        let today = Date.now.formatted(.iso8601.year().month().day())
        if draftDay != today {
            draftDay = today
            plans = ""
            blockers = ""
        }
        days = Standup.recentActiveDays(before: .now, in: store.events, limit: 5)
        day = days.first
        rebuild()
    }

    private func rebuild() {
        sections = Standup.sections(events: store.events, projects: store.projectsByID, previousDay: day, deploys: store.pendingDeploys)
        edits = [:]
    }

    private func binding(for item: StandupItem) -> Binding<String> {
        Binding(get: { edits[item.id] ?? item.text }, set: { edits[item.id] = $0 })
    }

    private func chipTitle(_ date: Date) -> String {
        if Calendar.current.isDateInYesterday(date) { return "ontem" }
        let weekday = date.formatted(.dateTime.weekday(.abbreviated)).replacingOccurrences(of: ".", with: "").lowercased()
        return "\(weekday) \(date.formatted(.dateTime.day(.twoDigits).month(.twoDigits)))"
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // HTML para quem entende formatação (Teams, Slack, e-mail); texto puro para o resto.
        pasteboard.setString(rendered.html, forType: .html)
        pasteboard.setString(rendered.plain, forType: .string)
        copied = true
    }
}

private struct DayChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.primary : Color.primary.opacity(0.07), in: Capsule())
                .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : .primary)
                .fontWeight(isSelected ? .semibold : .regular)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Item do standup; o texto é editável no lugar.
private struct ItemRow: View {
    @Binding var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("–").foregroundStyle(.tertiary)
            TextField("Item", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
        }
        .padding(.leading, 15)
    }
}
