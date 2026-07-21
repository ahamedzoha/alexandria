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
}

struct LibraryItem: Decodable, Identifiable, Sendable, Hashable {
    let id: String
    let media: Media?

    struct Media: Decodable, Sendable, Hashable {
        let metadata: Metadata?
        let duration: Double?
        let numTracks: Int?
    }

    struct Metadata: Decodable, Sendable, Hashable {
        let title: String?
        let authorName: String?
        let narratorName: String?
    }

    var title: String { media?.metadata?.title ?? "Untitled" }
    var author: String { media?.metadata?.authorName ?? "Unknown author" }
    var narrator: String? { media?.metadata?.narratorName }
    var duration: Double? { media?.duration }
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

struct ProgressUpdate: Encodable, Sendable {
    let currentTime: Double
    let duration: Double
    let progress: Double
    let isFinished: Bool
}

// MARK: - Me / progress

struct MeResponse: Decodable, Sendable {
    let mediaProgress: [MediaProgress]?
}

struct MediaProgress: Decodable, Sendable {
    let libraryItemId: String?
    let progress: Double?
    let isFinished: Bool?
}
