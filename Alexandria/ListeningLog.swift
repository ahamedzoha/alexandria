import Foundation
import Observation

/// Per-day listening, by book, for Home's listening diary. The server's
/// listening stats only count clients that sync playback sessions (the ABS
/// apps) — Alexandria saves positions, not sessions — so the app logs the
/// seconds it actually plays, per local day and per library item, and the
/// server's days are added on top: true totals across the phone and this Mac.
@MainActor
@Observable
final class ListeningLog {
    /// "yyyy-MM-dd" (local) → library item id → seconds played in Alexandria.
    private(set) var days: [String: [String: Double]]

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "listeningLog.v2"
    private static let legacyKey = "listeningLog"   // v1: day → seconds, no books

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.dictionary(forKey: Self.key) as? [String: [String: Double]] {
            days = stored
        } else if let legacy = defaults.dictionary(forKey: Self.legacyKey) as? [String: Double] {
            // Book unknown for v1 seconds; they still count toward the day.
            days = legacy.mapValues { ["": $0] }
        } else {
            days = [:]
        }
    }

    /// Day totals, for the streak and week sums.
    var totals: [String: Double] { days.mapValues { $0.values.reduce(0, +) } }

    /// Credit `seconds` of `itemID` to `date`'s day; keeps ~four months.
    func add(_ seconds: Double, itemID: String, on date: Date = .now) {
        guard seconds > 0 else { return }
        days[Self.dayKey(date), default: [:]][itemID, default: 0] += seconds
        if days.count > 130 {
            let cutoff = Self.dayKey(date.addingTimeInterval(-120 * 86_400))
            days = days.filter { $0.key >= cutoff }
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
        /// Books listened to that day, most-listened first.
        let itemIDs: [String]
        var id: Date { date }
    }

    /// The seven days ending today, oldest first. Seconds: Alexandria's log
    /// plus the server's day totals. Books: Alexandria's per-book log plus
    /// whatever the server's recent sessions attribute to that day.
    nonisolated static func week(endingAt today: Date, local: [String: [String: Double]],
                                 server: [String: Double], serverItems: [String: [String: Double]] = [:],
                                 calendar: Calendar = .current) -> [Day] {
        let start = calendar.startOfDay(for: today)
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let key = dayKey(date, calendar: calendar)
            var byItem = local[key] ?? [:]
            for (item, seconds) in serverItems[key] ?? [:] { byItem[item, default: 0] += seconds }
            let localTotal = (local[key] ?? [:]).values.reduce(0, +)
            let ids = byItem.filter { !$0.key.isEmpty && $0.value > 0 }
                .sorted { $0.value > $1.value }
                .map(\.key)
            return Day(date: date, seconds: localTotal + (server[key] ?? 0), itemIDs: ids)
        }
    }

    /// The book listened to most across `days`, if any.
    nonisolated static func mostListened(in week: [Day], local: [String: [String: Double]],
                                         serverItems: [String: [String: Double]],
                                         calendar: Calendar = .current) -> String? {
        var totals: [String: Double] = [:]
        for day in week {
            let key = dayKey(day.date, calendar: calendar)
            for (item, s) in local[key] ?? [:] where !item.isEmpty { totals[item, default: 0] += s }
            for (item, s) in serverItems[key] ?? [:] where !item.isEmpty { totals[item, default: 0] += s }
        }
        return totals.max { $0.value < $1.value }?.key
    }

    /// Consecutive days with at least a minute of listening, counting back
    /// from today — or from yesterday while today hasn't started yet, so a
    /// streak doesn't read as broken at breakfast. Takes day totals.
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
