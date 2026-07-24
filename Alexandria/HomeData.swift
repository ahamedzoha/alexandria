import Foundation

/// Home-specific derived collections + personal listening math, as
/// Observation-tracked computed properties (same pattern as `visibleItems`
/// and `searchMatches`). Keeps the feature isolated from AppState's core.
extension AppState {
    /// One resumable thing — a book or a podcast episode — with its progress
    /// snapshot. The Home hero and Continue Listening shelf render these
    /// uniformly, so both media share a single "pick up where you left off"
    /// surface instead of podcasts living in a separate mechanism.
    enum ContinueEntry: Identifiable {
        case book(LibraryItem, ItemProgress)
        case episode(PodcastEpisode, show: LibraryItem, ItemProgress)

        var id: String {
            switch self {
            case .book(let item, _): return item.id
            case .episode(let episode, let show, _): return "\(show.id)|\(episode.id)"
            }
        }
        /// The library item playback and detail sheets target: the book
        /// itself, or the episode's owning show.
        var item: LibraryItem {
            switch self {
            case .book(let item, _): return item
            case .episode(_, let show, _): return show
            }
        }
        /// Set only for podcast entries — passing it to startPlayback resumes
        /// this exact episode instead of the show's resume heuristic.
        var episode: PodcastEpisode? {
            switch self {
            case .book: return nil
            case .episode(let episode, _, _): return episode
            }
        }
        var title: String {
            switch self {
            case .book(let item, _): return item.title
            case .episode(let episode, _, _): return episode.displayTitle
            }
        }
        /// The supporting line under the title: author for books, show name
        /// for episodes.
        var subtitle: String {
            switch self {
            case .book(let item, _): return item.author
            case .episode(_, let show, _): return show.title
            }
        }
        var progress: ItemProgress {
            switch self {
            case .book(_, let p), .episode(_, _, let p): return p
            }
        }
        var duration: Double? {
            switch self {
            case .book(let item, _): return item.duration
            case .episode(let episode, _, _): return episode.bestDuration
            }
        }
    }

    /// In-progress books, most-recently-played first.
    var continueListening: [LibraryItem] {
        items
            .filter {
                let p = progress(itemID: $0.id)
                return (p?.fraction ?? 0) > 0.001 && !(p?.isFinished ?? false)
            }
            .sorted { (progress(itemID: $0.id)?.lastUpdate ?? 0) > (progress(itemID: $1.id)?.lastUpdate ?? 0) }
    }

    /// Books and podcast episodes in progress, merged most-recently-played
    /// first — the single continue queue behind the hero + shelf. Episode
    /// entries re-check progress live so a finished/reset episode drops out
    /// immediately, without waiting for the next episodeResumes refresh.
    var continueQueue: [ContinueEntry] {
        let books = continueListening.compactMap { item in
            progress(itemID: item.id).map { ContinueEntry.book(item, $0) }
        }
        let episodes = episodeResumes.compactMap { resume -> ContinueEntry? in
            guard let p = progress(itemID: resume.item.id, episodeID: resume.episode.id),
                  p.fraction > 0.001, !p.isFinished else { return nil }
            return .episode(resume.episode, show: resume.item, p)
        }
        return Self.mergedContinue(books + episodes)
    }

    /// The single most-recently-played entry across both media (drives the
    /// hero card).
    var heroContinue: ContinueEntry? { continueQueue.first }

    /// Everything after the hero, for the Continue Listening shelf.
    var continueShelfEntries: [ContinueEntry] { Array(continueQueue.dropFirst()) }

    /// Pure merge: most recent `lastUpdate` first. Static so cross-media
    /// ordering is unit-testable without an AppState.
    static func mergedContinue(_ entries: [ContinueEntry]) -> [ContinueEntry] {
        entries.sorted { $0.progress.lastUpdate > $1.progress.lastUpdate }
    }

    /// Finished books, most-recently-finished first.
    var recentlyFinished: [LibraryItem] {
        items
            .filter { progress(itemID: $0.id)?.isFinished ?? false }
            .sorted { (progress(itemID: $0.id)?.lastUpdate ?? 0) > (progress(itemID: $1.id)?.lastUpdate ?? 0) }
    }

    /// A stable daily sample of untouched books for the Discover shelf. Seeded
    /// by day-of-epoch so it doesn't re-shuffle on every re-render.
    var discoverPicks: [LibraryItem] {
        var gen = SeededGenerator(seed: UInt64(Date().timeIntervalSince1970 / 86_400))
        return Array(
            items
                .filter {
                    let p = progress(itemID: $0.id)
                    return (p?.fraction ?? 0) <= 0.001 && !(p?.isFinished ?? false)
                }
                .shuffled(using: &gen)
                .prefix(18)
        )
    }

    // Scoped to the loaded library (not global progress) so the counts stay
    // consistent with the shelves and the completion ring never exceeds 100%.
    var finishedCount: Int {
        items.filter { progress(itemID: $0.id)?.isFinished ?? false }.count
    }

    var inProgressCount: Int {
        items.filter {
            let p = progress(itemID: $0.id)
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
        items.reduce(0.0) { $0 + (progress(itemID: $1.id)?.fraction ?? 0) * ($1.duration ?? 0) } / 3600
    }

    /// Podcast episodes for the Home "Latest Episodes" shelf: newest-published
    /// first, finished episodes dropped. Started episodes are excluded only
    /// when they actually made it onto the continue surfaces (hero / shelf) —
    /// excluding on raw progress instead would make an episode past the
    /// continue queue's resolution cap vanish from Home entirely.
    var recentEpisodes: [PodcastEpisode] {
        let onContinue = Set(episodeResumes.map { "\($0.item.id)|\($0.episode.id)" })
        return Self.freshEpisodes(from: fetchedRecentEpisodes, onContinueSurfaces: onContinue) { itemID, episodeID in
            progress(itemID: itemID, episodeID: episodeID)
        }
    }

    /// Pure filter/sort behind `recentEpisodes` (unit-testable without an
    /// AppState): drops finished episodes and ones already shown on the
    /// continue surfaces (keyed "itemID|episodeID"), newest first.
    static func freshEpisodes(
        from fetched: [PodcastEpisode],
        onContinueSurfaces: Set<String>,
        progress: (String, String) -> ItemProgress?
    ) -> [PodcastEpisode] {
        Array(
            fetched
                .filter { episode in
                    guard let itemID = episode.libraryItemId,
                          let p = progress(itemID, episode.id) else { return true }
                    if p.isFinished { return false }
                    if p.fraction <= 0.001 { return true }
                    return !onContinueSurfaces.contains("\(itemID)|\(episode.id)")
                }
                .sorted { $0.sortDate > $1.sortDate }
                .prefix(20)
        )
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
