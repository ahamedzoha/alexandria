import Foundation

// MARK: - Podcast episodes

struct PodcastEpisode: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let libraryItemId: String?
    let index: Int?
    let season: String?
    let episode: String?
    let episodeType: String?
    let title: String?
    let subtitle: String?
    let description: String?   // HTML from the feed
    let pubDate: String?
    let publishedAt: Int?      // epoch ms
    let addedAt: Int?          // epoch ms
    let duration: Double?      // seconds; only present on Expanded episodes
    let size: Int?
    let audioFile: EpisodeAudioFile?
    let podcast: PodcastShellInfo?   // only present on /recent-episodes results

    var bestDuration: Double? { duration ?? audioFile?.duration }
    /// Feed-order sort key: publish time, falling back to added time (epoch ms).
    var sortDate: Double { Double(publishedAt ?? addedAt ?? 0) }
    var publishedDate: Date? {
        guard let ms = publishedAt else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }
    var displayTitle: String { title ?? "Untitled episode" }
}

struct EpisodeAudioFile: Decodable, Hashable, Sendable {
    let ino: String?
    let duration: Double?
    let mimeType: String?
    let metadata: EpisodeFileMetadata?
}

struct EpisodeFileMetadata: Decodable, Hashable, Sendable {
    let filename: String?
    let size: Int?
}

/// Podcast Minified shell attached to each recent-episodes result.
struct PodcastShellInfo: Decodable, Hashable, Sendable {
    let metadata: PodcastShellMetadata?
    let coverPath: String?
    let numEpisodes: Int?
}

struct PodcastShellMetadata: Decodable, Hashable, Sendable {
    let title: String?
    let author: String?
}

// MARK: - API responses

/// GET /api/items/{id}?expanded=1&include=progress (podcast items carry episodes).
struct ItemExpandedResponse: Decodable, Sendable {
    let id: String?
    let mediaType: String?
    let media: Media?
    /// Attached by include=progress: the user's progress rows for this item
    /// (one per episode for podcasts).
    let userMediaProgress: [MediaProgress]?

    struct Media: Decodable, Sendable {
        let episodes: [PodcastEpisode]?
    }

    private enum CodingKeys: String, CodingKey {
        case id, mediaType, media, userMediaProgress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        media = try c.decodeIfPresent(Media.self, forKey: .media)
        // The server sends an array for podcasts but a single object for
        // books — normalize both shapes to an array.
        if let list = try? c.decodeIfPresent([MediaProgress].self, forKey: .userMediaProgress) {
            userMediaProgress = list
        } else if let single = try? c.decodeIfPresent(MediaProgress.self, forKey: .userMediaProgress) {
            userMediaProgress = [single]
        } else {
            userMediaProgress = nil
        }
    }

    var episodes: [PodcastEpisode] { media?.episodes ?? [] }
}

/// GET /api/libraries/{id}/recent-episodes
struct RecentEpisodesResponse: Decodable, Sendable {
    let episodes: [PodcastEpisode]
    let total: Int?
    let limit: Int?
    let page: Int?
}

/// PATCH /api/me/progress body — synthesized Encodable skips nil fields,
/// so only the provided values reach the server.
struct ProgressPatch: Encodable, Sendable {
    let currentTime: Double?
    let duration: Double?
    let progress: Double?
    let isFinished: Bool?
}
