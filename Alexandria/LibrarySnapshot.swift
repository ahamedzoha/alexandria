import Foundation

/// What a server's library looked like the last time Alexandria saw it —
/// enough to open, browse, resume and play downloads with no connection.
/// One file per server; the network refreshes over it on every launch.
struct LibrarySnapshot: Codable, Sendable {
    struct ProgressRow: Codable, Sendable {
        let key: AppState.ProgressKey
        let progress: AppState.ItemProgress
    }

    // 2: items looked up one at a time now carry their authors and series.
    static let currentVersion = 2

    var version = LibrarySnapshot.currentVersion
    var libraries: [Library] = []
    var selectedLibraryID: String?
    /// Each library's items as last loaded, by library id.
    var itemsByLibrary: [String: [LibraryItem]] = [:]
    var recentItems: [LibraryItem] = []
    var progress: [ProgressRow] = []
    var episodesByItem: [String: [PodcastEpisode]] = [:]
    var episodeResumes: [AppState.EpisodeResume] = []
    var recentEpisodes: [PodcastEpisode] = []
    /// Items known outside the loaded lists: other libraries' books in
    /// progress, the shows behind episodes, what's playing, downloads.
    var extraItems: [LibraryItem] = []
    var savedAt = Date()

    var progressMap: [AppState.ProgressKey: AppState.ItemProgress] {
        Dictionary(progress.map { ($0.key, $0.progress) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Reads and writes snapshots under Application Support/Alexandria/Library.
/// Writes are atomic and happen off the main thread.
struct LibrarySnapshotStore: Sendable {
    let directory: URL

    /// `directory` defaults to Application Support/Alexandria/Library; tests
    /// pass a temporary folder.
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alexandria/Library", isDirectory: true)
    }

    private func file(_ serverID: String) -> URL {
        directory.appendingPathComponent("\(serverID).json")
    }

    /// nil when there's no snapshot, or it's unreadable or from another version.
    func load(serverID: String) -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: file(serverID)),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data),
              snapshot.version == LibrarySnapshot.currentVersion else { return nil }
        return snapshot
    }

    func save(_ snapshot: LibrarySnapshot, serverID: String) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(serverID), options: .atomic)
    }

    func remove(serverID: String) {
        try? FileManager.default.removeItem(at: file(serverID))
    }

    /// Bytes on disk across every server's snapshot (Settings ▸ Storage).
    func totalSize() -> Int64 {
        directorySize(directory)
    }
}

/// Bytes used by the files under `url`, recursively.
func directorySize(_ url: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
    var total: Int64 = 0
    for case let file as URL in enumerator {
        let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
        if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
    }
    return total
}
