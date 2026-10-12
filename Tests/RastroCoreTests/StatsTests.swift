import Foundation
import Testing
@testable import RastroCore

struct StatsTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        c.firstWeekday = 1
        return c
    }()

    func day(_ string: String, hour: Int = 12) -> Date {
        let parts = string.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
    }

    @Test func countsPerDay() {
        let counts = Stats.dayCounts([day("2026-10-10", hour: 1), day("2026-10-10", hour: 23), day("2026-10-11")], calendar: calendar)
        #expect(counts[calendar.startOfDay(for: day("2026-10-10"))] == 2)
        #expect(counts[calendar.startOfDay(for: day("2026-10-11"))] == 1)
        #expect(counts.count == 2)
    }

    @Test func streakIncludingToday() {
        let days: Set = [day("2026-10-09"), day("2026-10-10"), day("2026-10-11"), day("2026-10-01"), day("2026-10-02")]
        let result = Stats.streaks(activeDays: days, today: day("2026-10-11"), calendar: calendar)
        #expect(result == Streaks(current: 3, longest: 3))
    }

    @Test func streakAliveWhenLastActivityWasYesterday() {
        let days: Set = [day("2026-10-09"), day("2026-10-10")]
        #expect(Stats.streaks(activeDays: days, today: day("2026-10-11"), calendar: calendar).current == 2)
    }

    @Test func streakBrokenAfterGap() {
        let days: Set = [day("2026-10-01"), day("2026-10-02"), day("2026-10-03"), day("2026-10-04"), day("2026-10-09")]
        let result = Stats.streaks(activeDays: days, today: day("2026-10-11"), calendar: calendar)
        #expect(result == Streaks(current: 0, longest: 4))
    }

    @Test func emptyStreaks() {
        #expect(Stats.streaks(activeDays: [], today: day("2026-10-11"), calendar: calendar) == Streaks(current: 0, longest: 0))
    }

    @Test func heatmapShape() {
        let weeks = Stats.heatmapWeeks(endingAt: day("2026-10-11"), weeks: 53, calendar: calendar)
        #expect(weeks.count == 53)
        #expect(weeks.allSatisfy { $0.count == 7 })
        // 2026-10-11 é domingo: primeiro dia da última semana.
        #expect(weeks.last?.first == calendar.startOfDay(for: day("2026-10-11")))
        #expect(calendar.dateComponents([.day], from: weeks[0][0], to: weeks[52][0]).day == 52 * 7)
    }
}
