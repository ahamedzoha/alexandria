import Foundation
import Observation

/// Per-day listening time, for Home's week. The server's listening stats only
/// count clients that sync playback sessions (the ABS apps) — Alexandria
/// saves positions, not sessions — so the app keeps its own log of seconds
/// actually played per local day and adds the server's days on top: true
/// totals across the phone and this Mac.
@MainActor
@Observable
final class ListeningLog {
    /// "yyyy-MM-dd" (local) → seconds played in Alexandria.
    private(set) var days: [String: Double]

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "listeningLog"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        days = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
    }

    /// Credit `seconds` of playback to `date`'s day; keeps ~four months.
    func add(_ seconds: Double, on date: Date = .now) {
        guard seconds > 0 else { return }
        days[Self.dayKey(date), default: 0] += seconds
        if days.count > 130 {
            days = days.filter { $0.key >= Self.dayKey(date.addingTimeInterval(-120 * 86_400)) }
        }
        defaults.set(days, forKey: Self.key)
    }

    // MARK: Pure

    nonisolated static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    struct Day: Identifiable, Equatable {
        let date: Date
        let seconds: Double
        var id: Date { date }
    }

    /// The seven days ending today, oldest first, local + server combined.
    nonisolated static func week(endingAt today: Date, local: [String: Double], server: [String: Double],
                                 calendar: Calendar = .current) -> [Day] {
        let start = calendar.startOfDay(for: today)
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let key = dayKey(date, calendar: calendar)
            return Day(date: date, seconds: (local[key] ?? 0) + (server[key] ?? 0))
        }
    }

    /// Consecutive days with at least a minute of listening, counting back
    /// from today — or from yesterday while today hasn't started yet, so a
    /// streak doesn't read as broken at breakfast.
    nonisolated static func streak(endingAt today: Date, local: [String: Double], server: [String: Double],
                                   calendar: Calendar = .current) -> Int {
        func listened(_ date: Date) -> Bool {
            let key = dayKey(date, calendar: calendar)
            return (local[key] ?? 0) + (server[key] ?? 0) >= 60
        }
        var day = calendar.startOfDay(for: today)
        if !listened(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while listened(day), count < 3650 {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }
}
