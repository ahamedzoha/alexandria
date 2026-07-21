import Foundation
import Observation

// MARK: - Persisted model

struct DownloadedTrack: Codable, Sendable {
    let fileName: String
    let startOffset: Double
    let duration: Double
}

struct StoredChapter: Codable, Sendable {
    let start: Double
    let end: Double
    let title: String
}

struct DownloadedBook: Codable, Identifiable, Sendable {
    var itemID: String
    var title: String
    var author: String
    var coverFileName: String?
    var tracks: [DownloadedTrack]
    var chapters: [StoredChapter]
    var duration: Double
    var savedProgress: Double
    var updatedAt: Double
    var id: String { itemID }
}

struct PendingProgress: Codable, Sendable {
    var currentTime: Double
    var duration: Double
}

/// Manages offline downloads: audio files on disk, a JSON index, and an
/// offline progress queue that flushes to the server when back online.
@MainActor
@Observable
final class DownloadStore {
    var downloadedBooks: [DownloadedBook] = []
    var activeDownloads: [String: Double] = [:]   // itemID -> 0...1 progress
    private var pending: [String: PendingProgress] = [:]

    init() {
        load()
    }

    // MARK: Queries

    func isDownloaded(_ itemID: String) -> Bool {
        downloadedBooks.contains { $0.itemID == itemID }
    }

    func book(_ itemID: String) -> DownloadedBook? {
        downloadedBooks.first { $0.itemID == itemID }
    }

    func isDownloading(_ itemID: String) -> Bool {
        activeDownloads[itemID] != nil
    }

    /// Rebuild a PlaybackInfo from local files so the player can play offline.
    func localSession(for itemID: String) -> PlaybackInfo? {
        guard let book = book(itemID) else { return nil }
        let tracks = book.tracks.enumerated().map { i, t in
            PlaybackInfo.AudioTrack(
                index: i,
                startOffset: t.startOffset,
                duration: t.duration,
                title: nil,
                contentUrl: audioDir(itemID).appendingPathComponent(t.fileName).absoluteString,
                mimeType: nil
            )
        }
        let chapters = book.chapters.map {
            PlaybackInfo.Chapter(start: $0.start, end: $0.end, title: $0.title)
        }
        return PlaybackInfo(
            id: nil,
            audioTracks: tracks,
            chapters: chapters,
            currentTime: book.savedProgress,
            duration: book.duration
        )
    }

    func localCoverURL(_ itemID: String) -> URL? {
        guard let name = book(itemID)?.coverFileName else { return nil }
        return coverDir().appendingPathComponent(name)
    }

    // MARK: Download

    func download(item: LibraryItem, session: PlaybackInfo, serverURL: String, token: String?, coverURL: URL?) async {
        let id = item.id
        guard !isDownloaded(id), activeDownloads[id] == nil else { return }
        activeDownloads[id] = 0

        let sorted = session.audioTracks.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        guard !sorted.isEmpty else { activeDownloads[id] = nil; return }

        do {
            let dir = audioDir(id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var tracks: [DownloadedTrack] = []
            for (i, track) in sorted.enumerated() {
                guard let content = track.contentUrl,
                      let url = resolveURL(content, serverURL: serverURL, token: token) else { continue }
                let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
                let dest = dir.appendingPathComponent("\(i).\(ext)")
                let (tmp, _) = try await URLSession.shared.download(from: url)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tmp, to: dest)
                tracks.append(DownloadedTrack(
                    fileName: "\(i).\(ext)",
                    startOffset: track.startOffset ?? 0,
                    duration: track.duration ?? 0
                ))
                activeDownloads[id] = Double(i + 1) / Double(sorted.count)
            }

            var coverName: String?
            if let coverURL, let (data, _) = try? await URLSession.shared.data(from: coverURL) {
                let coverFolder = coverDir()
                try? FileManager.default.createDirectory(at: coverFolder, withIntermediateDirectories: true)
                let coverFile = coverFolder.appendingPathComponent("\(id).img")
                try? data.write(to: coverFile)
                coverName = "\(id).img"
            }

            let lastDuration = sorted.last?.duration ?? 0
            let duration = session.duration ?? ((tracks.last?.startOffset ?? 0) + lastDuration)
            let book = DownloadedBook(
                itemID: id,
                title: item.title,
                author: item.author,
                coverFileName: coverName,
                tracks: tracks,
                chapters: (session.chapters ?? []).map {
                    StoredChapter(start: $0.start ?? 0, end: $0.end ?? 0, title: $0.title ?? "")
                },
                duration: duration,
                savedProgress: session.currentTime ?? 0,
                updatedAt: Date().timeIntervalSince1970
            )
            downloadedBooks.removeAll { $0.itemID == id }
            downloadedBooks.append(book)
            persist()
        } catch {
            try? FileManager.default.removeItem(at: audioDir(id))   // clean partial download
        }
        activeDownloads[id] = nil
    }

    func remove(_ itemID: String) {
        downloadedBooks.removeAll { $0.itemID == itemID }
        try? FileManager.default.removeItem(at: audioDir(itemID))
        if let cover = localCoverURL(itemID) { try? FileManager.default.removeItem(at: cover) }
        persist()
    }

    // MARK: Offline progress

    func saveProgress(itemID: String, currentTime: Double, duration: Double) {
        guard let idx = downloadedBooks.firstIndex(where: { $0.itemID == itemID }) else { return }
        downloadedBooks[idx].savedProgress = currentTime
        downloadedBooks[idx].updatedAt = Date().timeIntervalSince1970
        persist()
    }

    func queuePending(itemID: String, currentTime: Double, duration: Double) {
        pending[itemID] = PendingProgress(currentTime: currentTime, duration: duration)
        persistPending()
    }

    func flushPending(api: APIClient) async {
        guard !pending.isEmpty else { return }
        for (id, progress) in pending {
            do {
                try await api.updateProgress(itemID: id, currentTime: progress.currentTime, duration: progress.duration)
                pending[id] = nil
            } catch {
                // still offline; keep it queued
            }
        }
        persistPending()
    }

    // MARK: Storage

    private func resolveURL(_ content: String, serverURL: String, token: String?) -> URL? {
        var absolute = content
        if content.hasPrefix("/") {
            let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
            absolute = base + content
        }
        guard var comps = URLComponents(string: absolute) else { return nil }
        if let token, !token.isEmpty {
            let hasToken = comps.queryItems?.contains { $0.name == "token" } ?? false
            if !hasToken {
                var q = comps.queryItems ?? []
                q.append(URLQueryItem(name: "token", value: token))
                comps.queryItems = q
            }
        }
        return comps.url
    }

    private var baseDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Alexandria", isDirectory: true)
    }
    private func audioDir(_ itemID: String) -> URL {
        baseDir.appendingPathComponent("audio", isDirectory: true).appendingPathComponent(itemID, isDirectory: true)
    }
    private func coverDir() -> URL {
        baseDir.appendingPathComponent("covers", isDirectory: true)
    }
    private var indexFile: URL { baseDir.appendingPathComponent("index.json") }
    private var pendingFile: URL { baseDir.appendingPathComponent("pending.json") }

    private func load() {
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexFile),
           let books = try? JSONDecoder().decode([DownloadedBook].self, from: data) {
            downloadedBooks = books
        }
        if let data = try? Data(contentsOf: pendingFile),
           let queue = try? JSONDecoder().decode([String: PendingProgress].self, from: data) {
            pending = queue
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(downloadedBooks) {
            try? data.write(to: indexFile)
        }
    }

    private func persistPending() {
        if let data = try? JSONEncoder().encode(pending) {
            try? data.write(to: pendingFile)
        }
    }
}
