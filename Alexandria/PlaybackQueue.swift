import Foundation
import Observation
import SwiftUI   // MutableCollection.move(fromOffsets:toOffset:)
import UniformTypeIdentifiers

/// One thing waiting to play: a book, or a podcast episode with its show.
/// Codable so Up Next survives relaunches; Transferable so books and
/// episodes can be dragged onto it.
struct QueueEntry: Identifiable, Hashable, Codable, Sendable {
    let item: LibraryItem
    let episode: PodcastEpisode?

    /// Stable per book / episode, so the same thing can't be queued twice.
    var id: String { episode.map { "\(item.id)|\($0.id)" } ?? item.id }
    var title: String { episode?.displayTitle ?? item.title }
    var subtitle: String { episode == nil ? item.author : item.title }
    var duration: Double? { episode?.bestDuration ?? item.duration }

    /// A book or an episode; a podcast show itself isn't queueable.
    init?(item: LibraryItem, episode: PodcastEpisode?) {
        guard episode != nil || !item.isPodcast else { return nil }
        self.item = item
        self.episode = episode
    }
}

extension UTType {
    /// Declared in Info.plist (UTExportedTypeDeclarations).
    static let alexandriaQueueEntry = UTType(exportedAs: "com.alexandria.mac.queue-entry")
}

extension QueueEntry: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .alexandriaQueueEntry)
    }
}

/// Up Next, in two parts (as in Music and Podcasts):
/// - `manual` — what the user added with Play Next / Play Later or dragged in.
/// - `automatic` — filled from what's playing: a show's following unplayed
///   episodes, or a series' next unfinished books. Re-formed whenever
///   playback starts something; never holds anything already in `manual`.
/// When an item finishes, playback continues with `manual` first.
///
/// Saved per server (Application Support/Alexandria/Queues/<server>.json)
/// after every change, and restored by `bind(to:)` at launch and on a
/// server switch.
@MainActor
@Observable
final class PlaybackQueue {
    private(set) var manual: [QueueEntry] = []
    private(set) var automatic: [QueueEntry] = []
    /// What `automatic` continues: the show's or series' name.
    private(set) var automaticSource: String?

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var fileURL: URL?

    private struct Snapshot: Codable {
        var manual: [QueueEntry]
        var automatic: [QueueEntry]
        var automaticSource: String?
    }

    /// `directory` defaults to Application Support/Alexandria/Queues; tests
    /// pass a temporary folder.
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alexandria/Queues", isDirectory: true)
    }

    var upNext: [QueueEntry] { manual + automatic }
    var isEmpty: Bool { manual.isEmpty && automatic.isEmpty }

    // MARK: Editing

    func playNext(_ entry: QueueEntry) {
        dropEverywhere(entry.id)
        manual.insert(entry, at: 0)
        save()
    }

    func playLater(_ entry: QueueEntry) {
        dropEverywhere(entry.id)
        manual.append(entry)
        save()
    }

    /// Entries dropped at a position in Playing Next (a drag from the
    /// library, or from the automatic section).
    func insert(_ entries: [QueueEntry], at index: Int) {
        let incoming = entries.reduce(into: [QueueEntry]()) { list, entry in
            if !list.contains(where: { $0.id == entry.id }) { list.append(entry) }
        }
        let ids = Set(incoming.map(\.id))
        // Removing earlier copies shifts the target index up by however many sat above it.
        let shift = manual.prefix(min(index, manual.count)).filter { ids.contains($0.id) }.count
        incoming.forEach { dropEverywhere($0.id) }
        manual.insert(contentsOf: incoming, at: max(0, min(index - shift, manual.count)))
        save()
    }

    func remove(_ id: QueueEntry.ID) {
        dropEverywhere(id)
        save()
    }

    func remove(_ ids: Set<QueueEntry.ID>) {
        manual.removeAll { ids.contains($0.id) }
        automatic.removeAll { ids.contains($0.id) }
        save()
    }

    func moveManual(fromOffsets source: IndexSet, toOffset destination: Int) {
        manual.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func moveAutomatic(fromOffsets source: IndexSet, toOffset destination: Int) {
        automatic.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func clearManual() {
        manual = []
        save()
    }

    func clearAutomatic() {
        automatic = []
        automaticSource = nil
        save()
    }

    func clearAll() {
        manual = []
        automatic = []
        automaticSource = nil
        save()
    }

    /// The next thing to play, taken off the queue.
    func popNext() -> QueueEntry? {
        defer { save() }
        if !manual.isEmpty { return manual.removeFirst() }
        if !automatic.isEmpty { return automatic.removeFirst() }
        return nil
    }

    /// Something started playing: it leaves the queue, and the automatic
    /// part re-forms around it.
    func started(_ id: QueueEntry.ID, automatic entries: [QueueEntry], source: String?) {
        manual.removeAll { $0.id == id }
        let queued = Set(manual.map(\.id))
        automatic = entries.filter { $0.id != id && !queued.contains($0.id) }
        automaticSource = automatic.isEmpty ? nil : source
        save()
    }

    private func dropEverywhere(_ id: QueueEntry.ID) {
        manual.removeAll { $0.id == id }
        automatic.removeAll { $0.id == id }
    }

    // MARK: Persistence

    /// Switch to `serverID`'s saved queue (empty when it has none, or nil).
    func bind(to serverID: String?) {
        fileURL = serverID.map { directory.appendingPathComponent("\($0).json") }
        let snapshot = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        manual = snapshot?.manual ?? []
        automatic = snapshot?.automatic ?? []
        automaticSource = snapshot?.automaticSource
    }

    /// A removed server's queue goes with it.
    func forget(serverID: String) {
        let file = directory.appendingPathComponent("\(serverID).json")
        try? FileManager.default.removeItem(at: file)
        if fileURL == file { bind(to: nil) }
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = Snapshot(manual: manual, automatic: automatic, automaticSource: automaticSource)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Automatic fill (pure)

    /// A show's next unplayed episodes after `episodeID`, oldest first — the
    /// same direction auto-play has always continued in.
    nonisolated static func followingEpisodes(after episodeID: String, in episodes: [PodcastEpisode],
                                              isFinished: (PodcastEpisode) -> Bool,
                                              limit: Int = 25) -> [PodcastEpisode] {
        let chronological = episodes.sorted { $0.sortDate < $1.sortDate }
        guard let index = chronological.firstIndex(where: { $0.id == episodeID }) else { return [] }
        return Array(chronological.dropFirst(index + 1).filter { !isFinished($0) }.prefix(limit))
    }

    /// The series' next unfinished books after `item`, in reading order.
    /// Empty when the book has no series number to continue from.
    nonisolated static func followingBooks(after item: LibraryItem, in library: [LibraryItem],
                                           isFinished: (LibraryItem) -> Bool,
                                           limit: Int = 10) -> [LibraryItem] {
        guard let series = item.seriesBaseName,
              let position = item.seriesSequence(in: series) else { return [] }
        return Array(
            library
                .filter { $0.id != item.id && !isFinished($0) }
                .compactMap { book in book.seriesSequence(in: series).map { (book, $0) } }
                .filter { $0.1 > position }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
                .prefix(limit)
        )
    }
}
