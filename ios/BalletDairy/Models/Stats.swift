import Foundation

struct PracticeStats {
    struct Count: Identifiable { let id: String; let label: String; let value: Int }
    struct Week: Identifiable { var id: Date { start }; let start: Date; let minutes: Int }

    var classes = 0
    var minutes = 0
    var currentStreak = 0
    var longestStreak = 0
    var uniqueMovements = 0
    var topMovements: [Count] = []
    var byCategory: [Count] = []
    var byClassType: [Count] = []
    var weekly: [Week] = []

    var hoursLabel: String {
        let h = Double(minutes) / 60
        return h < 10 ? String(format: "%.1f", h) : String(Int(h.rounded()))
    }
}

enum StatsRange: String, CaseIterable, Identifiable {
    case month = "Month", year = "Year", all = "All time"
    var id: String { rawValue }
}

enum StatsEngine {
    /// - Parameters:
    ///   - interval: entries outside are ignored (nil = everything). Streaks always use all entries.
    ///   - weeks: how many trailing weeks to chart, ending at `now`'s week.
    static func compute(entries: [DiaryEntry], interval: DateInterval?, library: MovementLibrary,
                        now: Date = .now, weeks: Int = 8, calendar: Calendar = .current) -> PracticeStats {
        let practiced = entries.filter(\.isPracticed)
        let inRange = practiced.filter { interval?.contains($0.day) ?? true }
        var s = PracticeStats()
        s.classes = inRange.count
        s.minutes = inRange.reduce(0) { $0 + $1.durationMinutes }

        // movements
        var moveCounts: [String: Int] = [:]
        for e in inRange { for id in Set(e.movementIDs) { moveCounts[id, default: 0] += 1 } }
        s.uniqueMovements = moveCounts.count
        s.topMovements = moveCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(6)
            .map { PracticeStats.Count(id: $0.key, label: library.movement($0.key)?.name ?? $0.key, value: $0.value) }

        var catCounts: [String: Int] = [:]
        for (id, n) in moveCounts { if let c = library.movement(id)?.category { catCounts[c, default: 0] += n } }
        s.byCategory = library.categories.compactMap { c in
            catCounts[c.id].map { PracticeStats.Count(id: c.id, label: c.name, value: $0) }
        }

        var typeCounts: [String: Int] = [:]
        for e in inRange { typeCounts[e.classType, default: 0] += 1 }
        s.byClassType = typeCounts.sorted { $0.value > $1.value }.map { PracticeStats.Count(id: $0.key, label: $0.key, value: $0.value) }

        // streaks over all practised days
        let days = Set(practiced.map { calendar.startOfDay(for: $0.day) })
        s.longestStreak = longestRun(days, calendar: calendar)
        s.currentStreak = currentRun(days, today: calendar.startOfDay(for: now), calendar: calendar)

        // weekly minutes
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now.startOfDay
        s.weekly = (0..<weeks).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            let mins = practiced.filter { $0.day >= start && $0.day < end }.reduce(0) { $0 + $1.durationMinutes }
            return PracticeStats.Week(start: start, minutes: mins)
        }
        return s
    }

    static func interval(for range: StatsRange, around date: Date, calendar: Calendar = .current) -> DateInterval? {
        switch range {
        case .month: return calendar.dateInterval(of: .month, for: date)
        case .year: return calendar.dateInterval(of: .year, for: date)
        case .all: return nil
        }
    }

    static func longestRun(_ days: Set<Date>, calendar: Calendar) -> Int {
        var best = 0
        for d in days {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: d), !days.contains(prev) else { continue }
            var len = 1, cur = d
            while let next = calendar.date(byAdding: .day, value: 1, to: cur), days.contains(next) { len += 1; cur = next }
            best = max(best, len)
        }
        return best
    }

    /// Consecutive days ending today — or yesterday, so a streak isn't "broken" before you've danced today.
    static func currentRun(_ days: Set<Date>, today: Date, calendar: Calendar) -> Int {
        var cur = today
        if !days.contains(cur) {
            guard let y = calendar.date(byAdding: .day, value: -1, to: today), days.contains(y) else { return 0 }
            cur = y
        }
        var n = 0
        while days.contains(cur) {
            n += 1
            guard let p = calendar.date(byAdding: .day, value: -1, to: cur) else { break }
            cur = p
        }
        return n
    }
}
