import Foundation

/// Home-specific derived collections + personal listening math, as
/// Observation-tracked computed properties (same pattern as `visibleItems`
/// and `searchMatches`). Keeps the feature isolated from AppState's core.
extension AppState {
    /// In-progress books, most-recently-played first.
    var continueListening: [LibraryItem] {
        items
            .filter {
                let p = progressByItem[$0.id]
                return (p?.fraction ?? 0) > 0.001 && !(p?.isFinished ?? false)
            }
            .sorted { (progressByItem[$0.id]?.lastUpdate ?? 0) > (progressByItem[$1.id]?.lastUpdate ?? 0) }
    }

    /// The single most-recently-played in-progress book (drives the hero card).
    var heroContinueItem: LibraryItem? { continueListening.first }

    /// Finished books, most-recently-finished first.
    var recentlyFinished: [LibraryItem] {
        items
            .filter { progressByItem[$0.id]?.isFinished ?? false }
            .sorted { (progressByItem[$0.id]?.lastUpdate ?? 0) > (progressByItem[$1.id]?.lastUpdate ?? 0) }
    }

    /// A stable daily sample of untouched books for the Discover shelf. Seeded
    /// by day-of-epoch so it doesn't re-shuffle on every re-render.
    var discoverPicks: [LibraryItem] {
        var gen = SeededGenerator(seed: UInt64(Date().timeIntervalSince1970 / 86_400))
        return Array(
            items
                .filter {
                    let p = progressByItem[$0.id]
                    return (p?.fraction ?? 0) <= 0.001 && !(p?.isFinished ?? false)
                }
                .shuffled(using: &gen)
                .prefix(18)
        )
    }

    // Scoped to the loaded library (not global progress) so the counts stay
    // consistent with the shelves and the completion ring never exceeds 100%.
    var finishedCount: Int {
        items.filter { progressByItem[$0.id]?.isFinished ?? false }.count
    }

    var inProgressCount: Int {
        items.filter {
            let p = progressByItem[$0.id]
            return (p?.fraction ?? 0) > 0.001 && !(p?.isFinished ?? false)
        }.count
    }

    /// Library size — the true total from stats when available, else the loaded set.
    var libraryTotal: Int { stats?.totalItems ?? items.count }

    var libraryCompletion: Double {
        guard libraryTotal > 0 else { return 0 }
        return min(1, Double(finishedCount) / Double(libraryTotal))
    }

    /// Approximate personal hours listened, summed over loaded items.
    var listenedHours: Double {
        items.reduce(0.0) { $0 + (progressByItem[$1.id]?.fraction ?? 0) * ($1.duration ?? 0) } / 3600
    }
}

/// Deterministic xorshift64 RNG so Discover's sample stays stable within a day
/// rather than jittering across SwiftUI re-renders.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
