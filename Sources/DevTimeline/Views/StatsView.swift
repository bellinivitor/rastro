import DevTimelineCore
import SwiftUI

struct StatsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let commits = store.events.filter { $0.kind == .commit }
        let counts = Stats.dayCounts(commits.map(\.date))
        let streaks = Stats.streaks(activeDays: Set(counts.keys))
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        let lastYear = commits.filter { $0.date >= yearAgo }
        let activeDays = counts.keys.filter { $0 >= yearAgo }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(lastYear.count) commits em \(activeDays) dias, nos últimos 12 meses.")
                        .font(.system(size: 28, weight: .semibold))
                    Text(streakSentence(streaks))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Atividade").font(.headline)
                    HeatmapView(counts: counts)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Projetos com mais commits").font(.headline)
                    ProjectRanking(commits: lastYear, projects: store.projectsByID)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Estatísticas")
    }

    private func streakSentence(_ streaks: Streaks) -> String {
        let record = streaks.longest == 1 ? "1 dia" : "\(streaks.longest) dias"
        switch streaks.current {
        case 0: return "Nenhuma sequência ativa agora. A maior foi de \(record)."
        case streaks.longest: return "Você está na sua maior sequência: \(record) seguidos."
        default: return "Sequência atual de \(streaks.current) dias. A maior foi de \(record)."
        }
    }
}

struct HeatmapView: View {
    let counts: [Date: Int]

    private let gap: CGFloat = 3
    private let labelColumn: CGFloat = 30
    private let monthRow: CGFloat = 18

    @State private var width: CGFloat = 0
    @State private var hovered: Date?

    private var weeks: [[Date]] { Stats.heatmapWeeks() }

    /// Desenhado em Canvas para se ajustar à largura sem impor largura mínima à janela.
    private func cellSize(for width: CGFloat) -> CGFloat {
        let count = CGFloat(weeks.count)
        return min(16, max(4, ((width - labelColumn - gap * (count - 1)) / count).rounded(.down)))
    }

    var body: some View {
        let weeks = weeks
        let cell = cellSize(for: width)
        let thresholds = levels(for: counts.values.filter { $0 > 0 })
        let today = Calendar.current.startOfDay(for: .now)

        VStack(alignment: .leading, spacing: 10) {
            Canvas { context, _ in
                let calendar = Calendar.current
                let step = cell + gap

                for (index, week) in weeks.enumerated() {
                    if let first = week.first(where: { calendar.component(.day, from: $0) == 1 }), index < weeks.count - 2 {
                        let label = Text(first, format: .dateTime.month(.abbreviated)).font(.caption).foregroundStyle(.secondary)
                        context.draw(label, at: CGPoint(x: labelColumn + CGFloat(index) * step, y: 0), anchor: .topLeading)
                    }
                    for (row, day) in week.enumerated() where day <= today {
                        let rect = CGRect(x: labelColumn + CGFloat(index) * step, y: monthRow + CGFloat(row) * step, width: cell, height: cell)
                        let shape = Path(roundedRect: rect, cornerRadius: min(3, cell / 4))
                        context.fill(shape, with: .color(color(count: counts[day] ?? 0, thresholds: thresholds)))
                        if day == hovered {
                            context.stroke(shape, with: .color(.primary), lineWidth: 1.5)
                        }
                    }
                }

                let symbols = calendar.shortWeekdaySymbols
                for row in [1, 3, 5] {
                    let label = Text(symbols[(calendar.firstWeekday - 1 + row) % 7]).font(.caption2).foregroundStyle(.secondary)
                    context.draw(label, at: CGPoint(x: 0, y: monthRow + CGFloat(row) * step + cell / 2), anchor: .leading)
                }
            }
            .frame(height: monthRow + 7 * cell + 6 * gap)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onContinuousHover { phase in
                guard case .active(let point) = phase else { hovered = nil; return }
                let step = cell + gap
                let column = Int((point.x - labelColumn) / step)
                let row = Int((point.y - monthRow) / step)
                if point.x >= labelColumn, point.y >= monthRow, weeks.indices.contains(column), (0..<7).contains(row), weeks[column][row] <= today {
                    hovered = weeks[column][row]
                } else {
                    hovered = nil
                }
            }

            HStack {
                Text(hovered.map { caption(day: $0, count: counts[$0] ?? 0) } ?? "Passe o mouse sobre um dia para ver os commits.")
                    .foregroundStyle(hovered == nil ? .tertiary : .secondary)
                Spacer()
                legend
            }
            .font(.caption)
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("menos").padding(.trailing, 2)
            RoundedRectangle(cornerRadius: 2).fill(Palette.heatEmpty).frame(width: 11, height: 11)
            ForEach(Palette.heat.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2).fill(Palette.heat[index]).frame(width: 11, height: 11)
            }
            Text("mais").padding(.leading, 2)
        }
        .foregroundStyle(.secondary)
    }

    /// Limites superiores dos 3 primeiros níveis, pelos quartis dos dias com atividade.
    private func levels(for values: [Int]) -> [Int] {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return [1, 2, 3] }
        return [0.25, 0.5, 0.75].map { sorted[min(sorted.count - 1, Int(Double(sorted.count) * $0))] }
    }

    private func color(count: Int, thresholds: [Int]) -> Color {
        guard count > 0 else { return Palette.heatEmpty }
        let level = thresholds.firstIndex { count <= $0 } ?? Palette.heat.count - 1
        return Palette.heat[level]
    }

    private func caption(day: Date, count: Int) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        switch count {
        case 0: return "Nenhum commit em \(date)"
        case 1: return "1 commit em \(date)"
        default: return "\(count) commits em \(date)"
        }
    }
}

private struct ProjectRanking: View {
    let commits: [Event]
    let projects: [Int64: Project]

    var body: some View {
        let ranking = Dictionary(grouping: commits.compactMap(\.projectID), by: { $0 })
            .compactMap { id, list in projects[id].map { ($0, list.count) } }
            .sorted { $0.1 > $1.1 }
            .prefix(10)
        let top = ranking.first?.1 ?? 1

        if ranking.isEmpty {
            Text("Nenhum commit nos últimos 12 meses.").foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(Array(ranking), id: \.0.id) { project, count in
                    GridRow {
                        Text(project.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 200, alignment: .leading)
                        GeometryReader { geo in
                            UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                                .fill(Palette.bar)
                                .frame(width: max(3, geo.size.width * CGFloat(count) / CGFloat(top)))
                        }
                        .frame(height: 10)
                        Text("\(count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                    .help("\(count) commits em \(project.name)")
                }
            }
        }
    }
}
