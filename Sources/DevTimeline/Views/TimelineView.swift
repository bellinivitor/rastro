import AppKit
import DevTimelineCore
import SwiftUI

struct TimelineView: View {
    /// `nil` mostra todos os projetos; um conjunto mostra um projeto ou um grupo.
    let projectIDs: Set<Int64>?
    var title = "Timeline"

    @Environment(AppStore.self) private var store
    @AppStorage(AppSettings.rootPathKey) private var rootPath = ""

    @State private var search = ""
    @State private var kind: EventKind?
    /// Seleção da timeline: clique seleciona um, ⌘-clique soma, ⇧-clique pega o intervalo.
    @State private var selection: Set<Int64> = []
    @State private var selectionAnchor: Int64?
    @State private var epicDraft: EpicDraft?
    @State private var expandedIDs: Set<Int64> = []
    @State private var editingNote: Event?

    /// Eventos do recorte atual (projeto/grupo e busca), antes do filtro por tipo.
    private var scoped: [Event] {
        store.events.filter { event in
            (projectIDs == nil || event.projectID.map { projectIDs!.contains($0) } == true)
                && (search.isEmpty
                    || event.title.localizedCaseInsensitiveContains(search)
                    || (event.detail?.localizedCaseInsensitiveContains(search) ?? false)
                    || (store.project(for: event)?.name.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    private var filtered: [Event] {
        guard let kind else { return scoped }
        return scoped.filter { $0.kind == kind }
    }

    private var days: [(day: Date, events: [Event])] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        Group {
            if rootPath.isEmpty && store.events.isEmpty {
                ContentUnavailableView {
                    Label("Nenhuma pasta configurada", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Escolha a pasta onde ficam seus repositórios e clique em Escanear.")
                } actions: {
                    SettingsLink { Text("Abrir Ajustes") }
                }
            } else if store.events.isEmpty {
                ContentUnavailableView {
                    Label("Nada por aqui ainda", systemImage: "clock")
                } description: {
                    Text("Clique em Escanear (⌘R) para importar seus commits.")
                }
            } else if scoped.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ScrollView {
                    if filtered.isEmpty, let kind {
                        Text("Nenhum evento do tipo \(kind.label.lowercased()) aqui.")
                            .foregroundStyle(.secondary)
                            .padding(32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    LazyVStack(alignment: .leading, spacing: 30) {
                        ForEach(days, id: \.day) { group in
                            DaySection(
                                day: group.day, events: group.events, showsProject: (projectIDs?.count ?? 2) > 1,
                                selection: selection, expandedIDs: $expandedIDs,
                                onTap: handleTap,
                                onEditNote: { editingNote = $0 },
                                onNewEpic: { epicDraft = EpicDraft(events: [$0]) }
                            )
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    KindFilterBar(events: scoped, selection: $kind)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    let selected = filtered.filter { selection.contains($0.id) }
                    if selected.count > 1 {
                        EpicSelectionBar(
                            selected: selected,
                            onCreateEpic: { epicDraft = EpicDraft(events: selected) },
                            onClear: { selection = [] }
                        )
                    }
                }
            }
        }
        .focusedSceneValue(\.deployToggle, deployToggle)
        .sheet(item: $editingNote) { note in
            NoteEditorView(note: note)
        }
        .sheet(item: $epicDraft) { draft in
            EpicNameView(draft: draft, onDone: { selection = [] })
        }
        .navigationTitle(title)
        .searchable(text: $search, prompt: "Buscar")
    }
}

/// Filtro por tipo dentro da timeline: um chip por tipo, com a contagem do recorte atual.
/// Tipos sem eventos ficam de fora, exceto o selecionado.
private struct KindFilterBar: View {
    let events: [Event]
    @Binding var selection: EventKind?

    var body: some View {
        let counts = events.reduce(into: [EventKind: Int]()) { $0[$1.kind, default: 0] += 1 }
        HStack(spacing: 6) {
            KindChip(title: "Tudo", count: events.count, isSelected: selection == nil) { selection = nil }
            ForEach(EventKind.allCases.filter { counts[$0, default: 0] > 0 || $0 == selection }) { kind in
                KindChip(title: kind.label, count: counts[kind, default: 0], isSelected: selection == kind) {
                    selection = selection == kind ? nil : kind
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .frame(maxWidth: 780, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct KindChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).fontWeight(isSelected ? .semibold : .regular)
                Text("\(count)")
                    .monospacedDigit()
                    .opacity(isSelected ? 0.7 : 0.55)
            }
            .font(.callout)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : .primary)
            .background(isSelected ? Color.primary : Color.primary.opacity(0.07), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension TimelineView {
    private func handleTap(_ event: Event) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(event.id) { selection.remove(event.id) } else { selection.insert(event.id) }
            selectionAnchor = event.id
        } else if flags.contains(.shift), let anchor = selectionAnchor,
                  let from = filtered.firstIndex(where: { $0.id == anchor }),
                  let to = filtered.firstIndex(where: { $0.id == event.id }) {
            selection = Set(filtered[min(from, to)...max(from, to)].map(\.id))
        } else {
            selection = [event.id]
            selectionAnchor = event.id
            // Clique simples num commit também expande/recolhe a descrição.
            if event.kind == .commit {
                withAnimation(.snappy(duration: 0.2)) {
                    if expandedIDs.contains(event.id) { expandedIDs.remove(event.id) } else { expandedIDs.insert(event.id) }
                }
            }
        }
    }

    /// Ação do menu Deploy (⌘D) para o item selecionado (só com um item selecionado).
    private var deployToggle: DeployToggle? {
        guard selection.count == 1,
              let event = store.events.first(where: { selection.contains($0.id) }),
              event.projectID != nil, event.kind == .commit || event.kind == .pullRequest
        else { return nil }
        if let task = store.pendingDeploy(for: event) {
            return DeployToggle(title: "Remover lembrete de deploy") { store.deleteDeployTask(task) }
        }
        return DeployToggle(title: "Lembrar de fazer deploy") { store.remindDeploy(event) }
    }
}

/// Um dia: bloco de data à esquerda e o trilho de eventos à direita.
private struct DaySection: View {
    let day: Date
    let events: [Event]
    let showsProject: Bool
    let selection: Set<Int64>
    @Binding var expandedIDs: Set<Int64>
    var onTap: (Event) -> Void = { _ in }
    var onEditNote: (Event) -> Void = { _ in }
    var onNewEpic: (Event) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            DateBlock(day: day, count: events.count)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    RailRow(
                        event: event, isFirst: index == 0, isLast: index == events.count - 1, showsProject: showsProject,
                        isSelected: selection.contains(event.id),
                        isExpanded: expandedIDs.contains(event.id),
                        onToggleExpansion: { toggleExpansion(event) },
                        onEditNote: { onEditNote(event) },
                        onNewEpic: { onNewEpic(event) }
                    )
                    .onTapGesture { onTap(event) }
                    .accessibilityAction(named: expandedIDs.contains(event.id) ? "Recolher descrição" : "Ver descrição") {
                        toggleExpansion(event)
                    }
                }
            }
        }
    }
}

extension DaySection {
    /// Clique expande/recolhe a descrição; só commits têm descrição.
    fileprivate func toggleExpansion(_ event: Event) {
        guard event.kind == .commit else { return }
        withAnimation(.snappy(duration: 0.2)) {
            if expandedIDs.contains(event.id) { expandedIDs.remove(event.id) } else { expandedIDs.insert(event.id) }
        }
    }
}

private struct DateBlock: View {
    let day: Date
    let count: Int

    private var isCurrentYear: Bool {
        Calendar.current.isDate(day, equalTo: .now, toGranularity: .year)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day, format: .dateTime.day())
                .font(.system(size: 38, weight: .semibold).width(.compressed))
                .monospacedDigit()
                .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.accentColor : .primary)
            // Em pt-BR dia da semana e mês são minúsculos.
            Text(day.formatted(.dateTime.weekday(.wide)).lowercased())
                .font(.callout.weight(.medium))
            Text(day, format: isCurrentYear ? .dateTime.month(.wide) : .dateTime.month(.abbreviated).year())
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(count == 1 ? "1 evento" : "\(count) eventos")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }
}

/// Uma linha do trilho, no estilo `git log --graph`: marcador na cor do projeto ligado ao anterior e ao próximo.
/// Duas linhas no máximo (título e contexto); tipo e hora numa coluna fixa à direita para dar para escanear.
private struct RailRow: View {
    let event: Event
    let isFirst: Bool
    let isLast: Bool
    let showsProject: Bool
    let isSelected: Bool
    let isExpanded: Bool
    var onToggleExpansion: () -> Void = {}
    var onEditNote: () -> Void = {}
    var onNewEpic: () -> Void = {}

    @Environment(AppStore.self) private var store
    @State private var isHovering = false
    /// Corpo do commit: `nil` enquanto não carregou.
    @State private var body_: String?

    private var project: Project? { store.project(for: event) }
    private var tint: Color { project.map { Palette.project($0.colorHex) } ?? .secondary }
    private var message: CommitMessage { CommitMessage.parse(event.title) }

    private var canDeploy: Bool {
        event.projectID != nil && (event.kind == .commit || event.kind == .pullRequest)
    }

    /// Altura do centro da primeira linha de texto (corpo 13 pt), onde fica o marcador.
    private static let markerCenter: CGFloat = 9

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RailMarker(kind: event.kind, state: event.state, tint: tint)
                .padding(.top, Self.markerCenter - RailMarker.size / 2)
                .frame(width: 14)
            content
                .padding(.bottom, isLast ? 0 : 14)
            Spacer(minLength: 16)
            trailing
        }
        .fixedSize(horizontal: false, vertical: true)
        // Desenhado no fundo: ocupa a altura real da linha (inclusive o espaço até a próxima).
        .background(alignment: .topLeading) {
            RailLine(isFirst: isFirst, isLast: isLast, markerCenter: Self.markerCenter, gap: RailMarker.size / 2 + 2)
                .stroke(Color.primary.opacity(0.16), lineWidth: 2)
                .frame(width: 14)
        }
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
                .padding(.top, -5)
                .padding(.bottom, isLast ? -5 : 9)
        )
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu { contextMenu }
    }

    // MARK: Conteúdo

    @ViewBuilder
    private var content: some View {
        switch event.kind {
        case .commit:
            VStack(alignment: .leading, spacing: 3) {
                // Sem seleção de texto aqui: ela engole o clique que seleciona/expande a linha.
                Text(message.headline)
                    .lineLimit(isExpanded ? nil : 2)
                context {
                    if !message.details.isEmpty, !isExpanded {
                        Text(message.details.joined(separator: "; "))
                    }
                }
                if isExpanded {
                    commitDescription
                        .transition(.opacity)
                }
            }
            .task(id: isExpanded) {
                if isExpanded, body_ == nil { body_ = await store.commitBody(for: event) ?? "" }
            }
        case .pullRequest:
            VStack(alignment: .leading, spacing: 3) {
                Text(message.text)
                    .lineLimit(2)
                context { pullRequestSentence }
            }
        case .deploy:
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).lineLimit(2)
                context { Text("Deploy feito") }
            }
        case .note:
            VStack(alignment: .leading, spacing: 4) {
                // Nota sem título: o texto é a nota, sem destaque separado.
                if !event.title.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(event.title).fontWeight(.semibold)
                }
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .foregroundStyle(event.title.trimmingCharacters(in: .whitespaces).isEmpty ? .primary : .secondary)
                }
                context { EmptyView() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, -4)
        }
    }

    /// Segunda linha: projeto (quando a vista mistura projetos), o que for específico do evento e o aviso de deploy.
    @ViewBuilder
    private func context<Detail: View>(@ViewBuilder _ detail: () -> Detail) -> some View {
        let name = showsProject ? project?.name : nil
        let awaitingDeploy = store.pendingDeploy(for: event) != nil
        HStack(spacing: 8) {
            if let name {
                Text(name).fontWeight(.medium)
            }
            detail()
                .foregroundStyle(.tertiary)
            if let epic = store.epic(for: event) {
                Label(epic.name, systemImage: "square.stack.3d.up")
                    .foregroundStyle(.secondary)
                    .help("Na epic \(epic.name)")
            }
            if awaitingDeploy {
                Label("aguardando deploy", systemImage: "shippingbox")
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// Itens do título (os separados por " - "), corpo da mensagem e hash.
    private var commitDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.details.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(message.details.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("–").foregroundStyle(.tertiary)
                            Text(item)
                        }
                    }
                }
            }
            if let body = body_ {
                if !body.isEmpty {
                    Text(body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if let hash = event.commitHash {
                HStack(spacing: 8) {
                    Text(hash.prefix(8)).monospaced().foregroundStyle(.tertiary)
                    Button("Copiar hash") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(hash, forType: .string)
                    }
                    .buttonStyle(.link)
                    if body_ == "", message.details.isEmpty {
                        Text("Sem descrição além do título.").foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }
        }
        .font(.callout)
        .textSelection(.enabled)
        .padding(.top, 4)
    }

    /// "!32 mergeado em develop" ou "#60 aberto". A branch de origem é longa e a menos importante:
    /// fica no tooltip, para o destino nunca ser cortado.
    @ViewBuilder
    private var pullRequestSentence: some View {
        let verb: String = switch event.state {
        case "open": "aberto"
        case "closed": "fechado"
        default: "mergeado"
        }
        let branches = event.detail?.components(separatedBy: " → ")
        HStack(spacing: 4) {
            if let ref = event.ref {
                if let url = event.url.flatMap(URL.init(string:)) {
                    Link(ref, destination: url).help("Abrir no navegador")
                } else {
                    Text(ref)
                }
            }
            if let branches, branches.count == 2 {
                Text("\(verb) em \(branches[1])")
                    .help("Vindo de \(branches[0])")
            } else {
                Text(verb)
                // PR sem projeto local guarda o repositório no detalhe.
                if let detail = event.detail, project == nil { Text("em \(detail)") }
            }
        }
        .layoutPriority(1)
    }

    // MARK: Coluna da direita

    private var trailing: some View {
        HStack(spacing: 10) {
            if event.kind == .commit {
                Button(action: onToggleExpansion) {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isExpanded || isHovering || isSelected ? 1 : 0)
                .help(isExpanded ? "Recolher" : "Ver a descrição completa")
                .accessibilityLabel(isExpanded ? "Recolher descrição" : "Ver descrição")
            }
            if event.kind == .note {
                Button(action: onEditNote) {
                    Image(systemName: "pencil").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isSelected ? 1 : 0)
                .help("Editar nota")
                .accessibilityLabel("Editar nota \(event.displayTitle)")
            }
            if canDeploy { deployButton }
            Group {
                if let type = message.type, event.kind == .commit || event.kind == .pullRequest {
                    Text(type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18)))
                }
            }
            .frame(width: 58, alignment: .trailing)
            Text(event.date, format: .dateTime.hour().minute())
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.top, 1)
    }

    /// Aparece no hover ou na seleção; fica fixo (laranja) enquanto houver lembrete pendente.
    @ViewBuilder
    private var deployButton: some View {
        let pending = store.pendingDeploy(for: event)
        Button {
            if let pending { store.deleteDeployTask(pending) } else { store.remindDeploy(event) }
        } label: {
            Image(systemName: pending == nil ? "shippingbox" : "shippingbox.fill")
                .foregroundStyle(pending == nil ? Color.secondary : Color.orange)
        }
        .buttonStyle(.plain)
        .opacity(pending != nil || isHovering || isSelected ? 1 : 0)
        .help(pending == nil ? "Lembrar de fazer deploy (⌘D)" : "Remover lembrete de deploy (⌘D)")
        .accessibilityLabel(pending == nil ? "Lembrar de fazer deploy" : "Remover lembrete de deploy")
    }

    @ViewBuilder
    private var contextMenu: some View {
        if event.kind == .note {
            Button("Editar nota…", action: onEditNote)
            Button("Apagar nota", role: .destructive) { store.delete(event) }
        }
        if canDeploy {
            if let task = store.pendingDeploy(for: event) {
                Button("Marcar como deployado") { store.setDeployed(task, done: true) }
                Button("Remover lembrete de deploy") { store.deleteDeployTask(task) }
            } else {
                Button("Lembrar de fazer deploy") { store.remindDeploy(event) }
            }
        }
        if AppStore.canJoinEpic(event), let projectID = event.projectID {
            Divider()
            if let epic = store.epic(for: event) {
                Button("Tirar da epic \(epic.name)") { store.removeFromEpic([event]) }
            } else {
                Menu("Adicionar à epic") {
                    ForEach(store.openEpics(in: projectID)) { epic in
                        Button(epic.name) { store.add([event], to: epic) }
                    }
                    if !store.openEpics(in: projectID).isEmpty { Divider() }
                    Button("Nova epic…", action: onNewEpic)
                }
            }
        }
        if let link = event.url.flatMap(URL.init(string:)) {
            Link("Abrir \(event.ref ?? "PR") no navegador", destination: link)
        }
    }
}

/// O trilho de uma linha: chega por cima até perto do marcador e sai por baixo até o fim da linha,
/// com um respiro em volta do marcador para nada ficar atravessado.
private struct RailLine: Shape {
    let isFirst: Bool
    let isLast: Bool
    let markerCenter: CGFloat
    let gap: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        if !isFirst, markerCenter - gap > 0 {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: markerCenter - gap))
        }
        if !isLast {
            path.move(to: CGPoint(x: x, y: markerCenter + gap))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return path
    }
}

/// Marcadores desenhados, todos do mesmo tamanho: ponto (commit), nó de merge (PR mergeado),
/// anel (PR aberto/fechado), losango (deploy) e quadrado vazado (nota).
private struct RailMarker: View {
    static let size: CGFloat = 11

    let kind: EventKind
    let state: String?
    let tint: Color

    var body: some View {
        Group {
            switch kind {
            case .commit:
                Circle().fill(tint).padding(1)
            case .pullRequest where state == "merged":
                ZStack {
                    Circle().strokeBorder(tint, lineWidth: 2)
                    Circle().fill(tint).padding(3.5)
                }
            case .pullRequest:
                Circle().strokeBorder(state == "closed" ? Color.secondary : tint, lineWidth: 2)
            case .deploy:
                Rectangle().fill(tint).rotationEffect(.degrees(45)).padding(2)
            case .note:
                RoundedRectangle(cornerRadius: 2.5).strokeBorder(tint, lineWidth: 2)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }
}
