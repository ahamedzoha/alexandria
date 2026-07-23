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
    // nil for whole-book downloads, set for podcast episodes. Optional so
    // pre-episode index.json entries decode as nil (no custom migration init).
    var episodeID: String?
    var episodeTitle: String?
    var title: String
    var author: String
    var coverFileName: String?
    var tracks: [DownloadedTrack]
    var chapters: [StoredChapter]
    var duration: Double
    var savedProgress: Double
    var updatedAt: Double
    var id: String { episodeID.map { "\(itemID)|\($0)" } ?? itemID }
}

struct PendingProgress: Codable, Sendable {
    var currentTime: Double
    var duration: Double
    // Set for queued (un)finished marks so they flush even when the episode's
    // duration is unknown; nil derives the flag from time/duration as before.
    var isFinished: Bool? = nil
}

/// Manages offline downloads: audio files on disk, a JSON index, and an
/// offline progress queue that flushes to the server when back online.
@MainActor
@Observable
final class DownloadStore {
    var downloadedBooks: [DownloadedBook] = []
    var activeDownloads: [String: Double] = [:]   // itemID or "itemID|episodeID" -> 0...1 progress
    private var pending: [String: PendingProgress] = [:]
    /// Set when index.json exists but wouldn't decode — sweepOrphans must not
    /// treat every folder as orphaned against an index we couldn't read.
    private var indexDecodeFailed = false

    init() {
        load()
        sweepOrphans()
    }

    // MARK: Queries

    func isDownloaded(_ itemID: String, episodeID: String? = nil) -> Bool {
        downloadedBooks.contains { $0.itemID == itemID && $0.episodeID == episodeID }
    }

    func book(_ itemID: String, episodeID: String? = nil) -> DownloadedBook? {
        downloadedBooks.first { $0.itemID == itemID && $0.episodeID == episodeID }
    }

    func isDownloading(_ itemID: String, episodeID: String? = nil) -> Bool {
        activeDownloads[downloadKey(itemID, episodeID)] != nil
    }

    /// 0...1 fraction for an in-flight download, or nil when none is running.
    func downloadProgress(_ itemID: String, episodeID: String? = nil) -> Double? {
        activeDownloads[downloadKey(itemID, episodeID)]
    }

    /// Rebuild a PlaybackInfo from local files so the player can play offline.
    func localSession(for itemID: String, episodeID: String? = nil) -> PlaybackInfo? {
        guard let book = book(itemID, episodeID: episodeID) else { return nil }
        let dir = trackDir(itemID, episodeID: episodeID)
        let tracks = book.tracks.enumerated().map { i, t in
            PlaybackInfo.AudioTrack(
                index: i,
                startOffset: t.startOffset,
                duration: t.duration,
                title: nil,
                contentUrl: dir.appendingPathComponent(t.fileName).absoluteString,
                mimeType: nil
            )
        }
        let chapters = book.chapters.map {
            PlaybackInfo.Chapter(start: $0.start, end: $0.end, title: $0.title)
        }
        // Finished (or within a second of the end): restart from the top.
        let resumeTime = book.duration > 0 && book.savedProgress >= book.duration - 1 ? 0 : book.savedProgress
        return PlaybackInfo(
            id: nil,
            episodeId: episodeID,
            audioTracks: tracks,
            chapters: chapters,
            currentTime: resumeTime,
            duration: book.duration
        )
    }

    func localCoverURL(_ itemID: String) -> URL? {
        // Cover is stored once per item; any of its records may carry the name.
        guard let name = downloadedBooks.first(where: { $0.itemID == itemID && $0.coverFileName != nil })?.coverFileName else { return nil }
        return coverDir().appendingPathComponent(name)
    }

    // MARK: Download

    func download(item: LibraryItem, episode: PodcastEpisode? = nil, session: PlaybackInfo, serverURL: String, token: String?, coverURL: URL?) async {
        let id = item.id
        let episodeID = episode?.id
        let key = downloadKey(id, episodeID)
        guard !isDownloaded(id, episodeID: episodeID), activeDownloads[key] == nil else { return }
        activeDownloads[key] = 0

        let sorted = session.audioTracks.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        guard !sorted.isEmpty else { activeDownloads[key] = nil; return }

        do {
            let dir = trackDir(id, episodeID: episodeID)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var tracks: [DownloadedTrack] = []
            for (i, track) in sorted.enumerated() {
                guard let content = track.contentUrl,
                      let url = resolveURL(content, serverURL: serverURL, token: token) else { continue }
                let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
                let dest = dir.appendingPathComponent("\(i).\(ext)")
                let (tmp, response) = try await URLSession.shared.download(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw APIError(message: "Server returned error \(http.statusCode) for track \(i + 1).")
                }
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tmp, to: dest)
                tracks.append(DownloadedTrack(
                    fileName: "\(i).\(ext)",
                    startOffset: track.startOffset ?? 0,
                    duration: track.duration ?? 0
                ))
                activeDownloads[key] = Double(i + 1) / Double(sorted.count)
            }

            var coverName: String?
            var coverRequest: URLRequest?
            if let coverURL {
                var req = URLRequest(url: coverURL)
                if let token, !token.isEmpty {
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                coverRequest = req
            }
            if let coverRequest, let (data, _) = try? await URLSession.shared.data(for: coverRequest) {
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
                episodeID: episodeID,
                episodeTitle: episode?.displayTitle,
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
            downloadedBooks.removeAll { $0.itemID == id && $0.episodeID == episodeID }
            downloadedBooks.append(book)
            persist()
        } catch {
            try? FileManager.default.removeItem(at: trackDir(id, episodeID: episodeID))   // clean partial download
        }
        activeDownloads[key] = nil
    }

    func remove(_ itemID: String, episodeID: String? = nil) {
        let cover = localCoverURL(itemID)   // resolve before the records go away
        if let episodeID {
            downloadedBooks.removeAll { $0.itemID == itemID && $0.episodeID == episodeID }
            try? FileManager.default.removeItem(at: episodeDir(itemID, episodeID))
            // Last download gone for this item: drop its folder + cover too.
            if !downloadedBooks.contains(where: { $0.itemID == itemID }) {
                try? FileManager.default.removeItem(at: audioDir(itemID))
                if let cover { try? FileManager.default.removeItem(at: cover) }
            }
        } else {
            // Whole-item removal (also clears any episode downloads under it).
            downloadedBooks.removeAll { $0.itemID == itemID }
            try? FileManager.default.removeItem(at: audioDir(itemID))
            if let cover { try? FileManager.default.removeItem(at: cover) }
        }
        persist()
    }

    // MARK: Offline progress

    func saveProgress(itemID: String, episodeID: String? = nil, currentTime: Double, duration: Double) {
        guard let idx = downloadedBooks.firstIndex(where: { $0.itemID == itemID && $0.episodeID == episodeID }) else { return }
        downloadedBooks[idx].savedProgress = currentTime
        downloadedBooks[idx].updatedAt = Date().timeIntervalSince1970
        persist()
    }

    func queuePending(itemID: String, episodeID: String? = nil, currentTime: Double, duration: Double, isFinished: Bool? = nil) {
        pending[downloadKey(itemID, episodeID)] = PendingProgress(currentTime: currentTime, duration: duration, isFinished: isFinished)
        persistPending()
    }

    func flushPending(api: APIClient) async {
        guard !pending.isEmpty else { return }
        for (key, progress) in pending {
            let (itemID, episodeID) = splitKey(key)
            let fraction = progress.duration > 0 ? min(1, progress.currentTime / progress.duration) : 0
            let finished = progress.isFinished ?? (fraction >= 0.99)
            do {
                if progress.duration > 0 {
                    try await api.patchProgress(itemID: itemID, episodeID: episodeID,
                                                currentTime: progress.currentTime, duration: progress.duration,
                                                progress: finished ? 1 : fraction, isFinished: finished)
                } else {
                    // Queued mark without a known duration: send only the flag
                    // so we don't clobber the server's stored time with zeros.
                    try await api.patchProgress(itemID: itemID, episodeID: episodeID,
                                                progress: finished ? 1 : 0, isFinished: finished)
                }
                // Only clear if no newer update was queued while we were sending.
                if pending[key]?.currentTime == progress.currentTime,
                   pending[key]?.isFinished == progress.isFinished {
                    pending[key] = nil
                }
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
    private func episodeDir(_ itemID: String, _ episodeID: String) -> URL {
        audioDir(itemID).appendingPathComponent("episodes", isDirectory: true).appendingPathComponent(episodeID, isDirectory: true)
    }
    /// Folder holding a record's audio: the item folder for books, a
    /// per-episode subfolder for podcast episodes.
    private func trackDir(_ itemID: String, episodeID: String?) -> URL {
        episodeID.map { episodeDir(itemID, $0) } ?? audioDir(itemID)
    }
    /// Composite key for activeDownloads + the pending queue: plain itemID for
    /// books (so pre-episode persisted entries stay valid), "itemID|episodeID"
    /// for podcast episodes.
    private func downloadKey(_ itemID: String, _ episodeID: String?) -> String {
        episodeID.map { "\(itemID)|\($0)" } ?? itemID
    }
    private func splitKey(_ key: String) -> (itemID: String, episodeID: String?) {
        guard let bar = key.firstIndex(of: "|") else { return (key, nil) }
        return (String(key[..<bar]), String(key[key.index(after: bar)...]))
    }
    private func coverDir() -> URL {
        baseDir.appendingPathComponent("covers", isDirectory: true)
    }
    private var indexFile: URL { baseDir.appendingPathComponent("index.json") }
    private var pendingFile: URL { baseDir.appendingPathComponent("pending.json") }

    private func load() {
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexFile) {
            if let books = try? JSONDecoder().decode([DownloadedBook].self, from: data) {
                downloadedBooks = books
                persist()   // re-save migrates a pre-episode index to the current schema
            } else {
                indexDecodeFailed = true
            }
        }
        // Pre-episode pending entries were keyed by plain itemID, which is
        // exactly the composite key for episodeID nil — no migration needed.
        if let data = try? Data(contentsOf: pendingFile),
           let queue = try? JSONDecoder().decode([String: PendingProgress].self, from: data) {
            pending = queue
        }
    }

    /// Delete audio folders and stray .partial/tmp files the index doesn't
    /// reference — leftovers from downloads interrupted by an app quit (the
    /// in-download cleanup only runs when the download itself throws).
    private func sweepOrphans() {
        // Sweep only against an index that's absent or decoded cleanly.
        guard !indexDecodeFailed else { return }
        let fm = FileManager.default
        let audioRoot = baseDir.appendingPathComponent("audio", isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(at: audioRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for entry in entries {
            let itemID = entry.lastPathComponent
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir, downloadedBooks.contains(where: { $0.itemID == itemID }) else {
                try? fm.removeItem(at: entry)
                continue
            }
            // Prune episode folders that never made it into the index.
            let episodesRoot = entry.appendingPathComponent("episodes", isDirectory: true)
            if let episodeDirs = try? fm.contentsOfDirectory(at: episodesRoot, includingPropertiesForKeys: nil) {
                for epDir in episodeDirs where !downloadedBooks.contains(where: { $0.itemID == itemID && $0.episodeID == epDir.lastPathComponent }) {
                    try? fm.removeItem(at: epDir)
                }
            }
            // Half-written temp files inside kept folders.
            if let deep = fm.enumerator(at: entry, includingPropertiesForKeys: nil) {
                for case let file as URL in deep where ["partial", "tmp"].contains(file.pathExtension) {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(downloadedBooks)
            try data.write(to: indexFile, options: .atomic)
        } catch {
            print("[Alexandria] failed to write download index: \(error)")
        }
    }

    private func persistPending() {
        do {
            let data = try JSONEncoder().encode(pending)
            try data.write(to: pendingFile, options: .atomic)
        } catch {
            print("[Alexandria] failed to write pending progress queue: \(error)")
        }
    }
}
