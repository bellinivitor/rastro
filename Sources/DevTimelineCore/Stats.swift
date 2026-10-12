import Foundation

public struct Streaks: Equatable, Sendable {
    public let current: Int
    public let longest: Int
}

public enum Stats {
    /// Quantidade de eventos por dia (chave = início do dia).
    public static func dayCounts(_ dates: [Date], calendar: Calendar = .current) -> [Date: Int] {
        dates.reduce(into: [:]) { counts, date in
            counts[calendar.startOfDay(for: date), default: 0] += 1
        }
    }

    /// A sequência atual continua viva se o último dia ativo foi hoje ou ontem.
    public static func streaks(activeDays: Set<Date>, today: Date = .now, calendar: Calendar = .current) -> Streaks {
        let days = Set(activeDays.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return Streaks(current: 0, longest: 0) }

        var longest = 0
        var run = 0
        var previous: Date?
        for day in days.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        let todayStart = calendar.startOfDay(for: today)
        var cursor = days.contains(todayStart)
            ? todayStart
            : calendar.date(byAdding: .day, value: -1, to: todayStart)!
        var current = 0
        while days.contains(cursor) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return Streaks(current: current, longest: longest)
    }

    /// Semanas (colunas) de 7 dias terminando na semana de `today`, para o heatmap.
    public static func heatmapWeeks(endingAt today: Date = .now, weeks: Int = 53, calendar: Calendar = .current) -> [[Date]] {
        let todayStart = calendar.startOfDay(for: today)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: todayStart)!.start
        let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart)!
        return (0..<weeks).map { week in
            let start = calendar.date(byAdding: .weekOfYear, value: week, to: firstWeek)!
            return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        }
    }
}
