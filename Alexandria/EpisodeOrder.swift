import Foundation

/// A podcast's episode order — chosen per show and remembered, like Apple
/// Podcasts' "Episode Order". It sorts the episode list, and decides where a
/// show-level Play starts. Auto-play next always continues chronologically
/// (to the next newer unfinished episode), which suits both.
enum EpisodeOrder: String, CaseIterable, Identifiable, Sendable {
    case newestFirst, oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        }
    }

    /// Serial shows are told in sequence, so they start oldest-first;
    /// episodic ones (the feed default) newest-first.
    static func defaultOrder(podcastType: String?) -> EpisodeOrder {
        podcastType?.lowercased() == "serial" ? .oldestFirst : .newestFirst
    }

    func sorted(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
        switch self {
        case .newestFirst: episodes.sorted { $0.sortDate > $1.sortDate }
        case .oldestFirst: episodes.sorted { $0.sortDate < $1.sortDate }
        }
    }

    /// Where a show-level Play lands when nothing is mid-listen.
    /// Oldest First: just after the last finished episode, else the oldest
    /// unplayed one — listening straight through. Newest First: the next
    /// newer episode after the latest finished one, else the newest.
    func startingEpisode(in episodes: [PodcastEpisode],
                         isFinished: (PodcastEpisode) -> Bool) -> PodcastEpisode? {
        let chronological = episodes.sorted { $0.sortDate < $1.sortDate }
        if let lastFinished = chronological.lastIndex(where: isFinished),
           let next = chronological.dropFirst(lastFinished + 1).first(where: { !isFinished($0) }) {
            return next
        }
        switch self {
        case .oldestFirst: return chronological.first(where: { !isFinished($0) }) ?? chronological.first
        case .newestFirst: return chronological.last
        }
    }

    /// Auto-play's next episode: the next newer unfinished one, whatever
    /// the list order.
    static func nextEpisode(after episodeID: String, in episodes: [PodcastEpisode],
                            isFinished: (PodcastEpisode) -> Bool) -> PodcastEpisode? {
        let chronological = episodes.sorted { $0.sortDate < $1.sortDate }
        guard let index = chronological.firstIndex(where: { $0.id == episodeID }) else { return nil }
        return chronological.dropFirst(index + 1).first { !isFinished($0) }
    }
}
