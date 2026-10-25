import Foundation

// MARK: - Auth

struct LoginResponse: Decodable, Sendable {
    let user: User
    struct User: Decodable, Sendable {
        let token: String?
        let username: String?
    }
}

// MARK: - Libraries

struct LibrariesResponse: Decodable, Sendable {
    let libraries: [Library]
}

struct Library: Decodable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let mediaType: String?
}

// MARK: - Items

struct ItemsResponse: Decodable, Sendable {
    let results: [LibraryItem]
    let total: Int?   // whole-library count, across every page
}

struct LibraryItem: Decodable, Identifiable, Sendable, Hashable {
    let id: String
    let mediaType: String?   // "book" | "podcast"
    let media: Media?
    let addedAt: Double?   // epoch ms; powers the Recently Added shelf

    struct Media: Decodable, Sendable, Hashable {
        let metadata: Metadata?
        let duration: Double?
        let numTracks: Int?
        let numEpisodes: Int?   // Podcast Minified only
    }

    struct Metadata: Decodable, Sendable, Hashable {
        let title: String?
        let authorName: String?
        let author: String?       // podcasts use a plain author string
        let narratorName: String?
        let seriesName: String?
        let description: String?
        let type: String?         // podcasts: "episodic" | "serial"
    }

    var title: String { media?.metadata?.title ?? "Untitled" }
    var author: String { media?.metadata?.authorName ?? media?.metadata?.author ?? "Unknown author" }
    var narrator: String? { media?.metadata?.narratorName }
    var duration: Double? { media?.duration }
    var numEpisodes: Int? { media?.numEpisodes }
    var isPodcast: Bool { mediaType == "podcast" }

    /// "Harry Potter #2" -> "Harry Potter" (drops the trailing sequence number).
    var seriesBaseName: String? {
        guard let raw = media?.metadata?.seriesName, !raw.isEmpty else { return nil }
        if let hash = raw.range(of: " #") {
            return String(raw[raw.startIndex..<hash.lowerBound])
        }
        return raw
    }

    /// Position within `series` ("The Dark Tower #7" → 7). The minified
    /// seriesName lists every series a book belongs to ("A #2, B #5"), and
    /// sequences can be fractional ("1.5" for a novella).
    func seriesSequence(in series: String) -> Double? {
        guard let raw = media?.metadata?.seriesName else { return nil }
        for entry in raw.components(separatedBy: ", ") {
            guard let hash = entry.range(of: " #", options: .backwards),
                  entry[..<hash.lowerBound] == series else { continue }
            return Double(entry[hash.upperBound...].prefix { $0.isNumber || $0 == "." })
        }
        return nil
    }
}

// MARK: - Playback

struct PlayRequest: Encodable, Sendable {
    struct DeviceInfo: Encodable, Sendable {
        let clientName = "Alexandria"
        let clientVersion = "0.1"
        let deviceId = "alexandria-mac"
    }
    let deviceInfo = DeviceInfo()
    let mediaPlayer = "AVPlayer"
    let forceDirectPlay = true
    let supportedMimeTypes = [
        "audio/flac", "audio/mpeg", "audio/mp4", "audio/aac",
        "audio/ogg", "audio/x-m4b", "audio/x-m4a",
    ]
}

struct PlaybackInfo: Decodable, Sendable {
    let id: String?
    // Set on podcast episode sessions. Defaulted var so DownloadStore's
    // memberwise rebuild of offline sessions keeps compiling.
    var episodeId: String? = nil
    let audioTracks: [AudioTrack]
    let chapters: [Chapter]?
    let currentTime: Double?
    let duration: Double?

    struct AudioTrack: Decodable, Sendable {
        let index: Int?
        let startOffset: Double?
        let duration: Double?
        let title: String?
        let contentUrl: String?
        let mimeType: String?
    }

    struct Chapter: Decodable, Sendable {
        let start: Double?
        let end: Double?
        let title: String?
    }
}

// MARK: - Authors

struct AuthorsResponse: Decodable, Sendable {
    let authors: [AuthorRef]
}

struct AuthorRef: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let imagePath: String?
}

/// GET /api/authors/{id} — the author record with its bio.
struct AuthorDetail: Decodable, Identifiable, Sendable {
    let id: String
    let name: String?
    let description: String?
    let imagePath: String?
}

// MARK: - Item detail (expanded)

struct ItemDetail: Decodable, Sendable {
    let media: Media?
    let libraryFiles: [LibraryFile]?

    struct LibraryFile: Decodable, Sendable {}

    struct Media: Decodable, Sendable {
        let metadata: Meta?
        let tags: [String]?
        let audioFiles: [AudioFile]?
        let chapters: [Chapter]?
        let duration: Double?
        let size: Double?

        struct AudioFile: Decodable, Sendable {}
        struct Chapter: Decodable, Sendable {
            let start: Double?
            let title: String?
        }
        struct Meta: Decodable, Sendable {
            let title: String?
            let subtitle: String?
            let authorName: String?
            let narratorName: String?
            let seriesName: String?
            let authors: [Credit]?      // books: [{id, name}]
            let narrators: [String]?
            let series: [SeriesEntry]?  // books: [{id, name, sequence}]
            let genres: [String]?
            let publishedYear: String?
            let publisher: String?
            let description: String?
            let language: String?
            let isbn: String?
            let asin: String?
        }
        struct Credit: Decodable, Sendable {
            let id: String?
            let name: String?
        }
        struct SeriesEntry: Decodable, Sendable {
            let id: String?
            let name: String?
            let sequence: String?
        }
    }
}

// MARK: - Library stats

struct LibraryStats: Decodable, Sendable {
    let totalItems: Int?
    let totalAuthors: Int?
    let totalGenres: Int?
    let totalDuration: Double?
    let totalSize: Double?
    let numAudioTracks: Int?
    let longestItems: [StatItem]?
    let largestItems: [StatItem]?
    let authorsWithCount: [StatCount]?
    let genresWithCount: [StatCount]?

    struct StatItem: Decodable, Sendable {
        let id: String?
        let title: String?
        let duration: Double?
        let size: Double?
    }

    struct StatCount: Decodable, Sendable {
        let name: String?
        let genre: String?
        let count: Int?
        let numBooks: Int?
        var label: String { name ?? genre ?? "—" }
        var value: Int { count ?? numBooks ?? 0 }
    }
}

// MARK: - Me / progress

struct MeResponse: Decodable, Sendable {
    let mediaProgress: [MediaProgress]?
}

struct MediaProgress: Decodable, Sendable {
    let libraryItemId: String?
    let episodeId: String?   // set for podcast episode progress
    let progress: Double?
    let currentTime: Double?  // seconds
    let duration: Double?     // seconds
    let isFinished: Bool?
    let lastUpdate: Double?   // epoch ms; powers "jump back in" ordering

    /// Completion 0...1, from the position when the server has one. The
    /// stored `progress` can go stale: after another client (Plappa) set it,
    /// this server kept updating currentTime on every Alexandria save while
    /// `progress` stayed frozen — so trusting it snapped Home's bars back to
    /// that old value on every sync.
    var fraction: Double {
        if isFinished == true { return 1 }
        if let currentTime, let duration, duration > 0 {
            return min(1, max(0, currentTime / duration))
        }
        return progress ?? 0
    }
}
