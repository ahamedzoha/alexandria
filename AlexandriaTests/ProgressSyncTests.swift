import XCTest
@testable import Alexandria

/// The offline progress queue and the "whose position is newer" decisions
/// behind 0.5.2's sync fixes. DownloadStore runs against a temporary folder.
@MainActor
final class ProgressSyncTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Flushes and returns what was sent, as "item|episode@time".
    private func flush(_ store: DownloadStore, server: String? = "srv-a",
                       superseded: @escaping (String, String?, Double) -> Bool = { _, _, _ in false },
                       fail: Error? = nil) async -> [String] {
        var sent: [String] = []
        await store.flushPending(serverID: server, isSuperseded: superseded) { itemID, episodeID, progress in
            if let fail { throw fail }
            sent.append("\(itemID)|\(episodeID ?? "-")@\(progress.currentTime)")
        }
        return sent
    }

    // MARK: Queue

    func testNewerSuccessfulWriteClearsTheOlderQueuedEntry() async {
        // The audit scenario: t=100 fails and queues; t=115 then succeeds.
        // Flushing the queued t=100 afterwards would move the server back.
        let store = DownloadStore(baseDir: dir)
        store.queuePending(itemID: "book", currentTime: 100, duration: 3600, now: 1_000)
        store.clearPending(itemID: "book", queuedBefore: 2_000)
        let sent = await flush(store)
        XCTAssertEqual(sent, [])
        XCTAssertTrue(store.pending.isEmpty)
    }

    func testClearKeepsAnEntryQueuedAfterTheWriteStarted() async {
        let store = DownloadStore(baseDir: dir)
        store.queuePending(itemID: "book", currentTime: 130, duration: 3600, now: 3_000)
        store.clearPending(itemID: "book", queuedBefore: 2_000)
        let sent = await flush(store)
        XCTAssertEqual(sent, ["book|-@130.0"])
    }

    func testEntryOvertakenByNewerProgressIsDroppedUnsent() async {
        // Queued offline at 10:00; the phone kept listening and the server
        // row is from 11:00 — the queued position must not be sent.
        let store = DownloadStore(baseDir: dir)
        store.queuePending(itemID: "book", episodeID: "ep", currentTime: 100, duration: 3600, now: 1_000)
        let sent = await flush(store, superseded: { item, episode, queuedAt in
            item == "book" && episode == "ep" && queuedAt < 5_000
        })
        XCTAssertEqual(sent, [])
        XCTAssertTrue(store.pending.isEmpty)
    }

    func testLegacyEntryWithoutTimestampStillFlushes() async throws {
        // A pending.json written by 0.5.1 or earlier has no queuedAt.
        let legacy = #"{ "book": { "currentTime": 42, "duration": 3600 } }"#
        try Data(legacy.utf8).write(to: dir.appendingPathComponent("pending.json"))
        let store = DownloadStore(baseDir: dir)
        let sent = await flush(store, superseded: { _, _, _ in true })
        XCTAssertEqual(sent, ["book|-@42.0"])
    }

    func testFailedSendKeepsTheEntryQueued() async {
        let store = DownloadStore(baseDir: dir)
        store.queuePending(itemID: "book", currentTime: 100, duration: 3600, now: 1_000)
        _ = await flush(store, fail: URLError(.notConnectedToInternet))
        XCTAssertEqual(store.pending.count, 1)
    }

    func testOverlappingFlushesSendEachEntryOnce() async {
        let store = DownloadStore(baseDir: dir)
        store.queuePending(itemID: "book", currentTime: 100, duration: 3600, now: 1_000)
        var sends = 0
        let send: (String, String?, PendingProgress) async throws -> Void = { _, _, _ in
            sends += 1
            try await Task.sleep(for: .milliseconds(50))   // still in flight when the second call arrives
        }
        async let first: Void = store.flushPending(serverID: nil, isSuperseded: { _, _, _ in false }, send: send)
        async let second: Void = store.flushPending(serverID: nil, isSuperseded: { _, _, _ in false }, send: send)
        _ = await (first, second)
        XCTAssertEqual(sends, 1)
    }

    func testEntriesOnlyFlushToTheServerTheyCameFrom() async {
        let store = DownloadStore(baseDir: dir)
        store.queuePending(itemID: "mine", currentTime: 10, duration: 3600, serverID: "srv-a", now: 1_000)
        store.queuePending(itemID: "theirs", currentTime: 20, duration: 3600, serverID: "srv-b", now: 1_000)
        let sent = await flush(store, server: "srv-a")
        XCTAssertEqual(sent, ["mine|-@10.0"])
        XCTAssertNotNil(store.pending["theirs"], "srv-b's entry waits for srv-b")
    }

    func testRemovingAServerDropsItsQueuedProgress() {
        let store = DownloadStore(baseDir: dir)
        store.queuePending(itemID: "mine", currentTime: 10, duration: 3600, serverID: "srv-a", now: 1_000)
        store.queuePending(itemID: "theirs", currentTime: 20, duration: 3600, serverID: "srv-b", now: 1_000)
        store.dropPending(serverID: "srv-b")
        XCTAssertEqual(Array(store.pending.keys), ["mine"])
    }

    func testNotFoundStopsRetryingForever() async {
        // Item deleted on the server (or queued against another one): a 404
        // used to be retried every 45 seconds, indefinitely.
        let store = DownloadStore(baseDir: dir)
        store.queuePending(itemID: "gone", currentTime: 10, duration: 3600, serverID: "srv-a", now: 1_000)
        _ = await flush(store, fail: APIError(message: "Server returned error 404.", status: 404))
        XCTAssertTrue(store.pending.isEmpty)
    }

    // MARK: Finished

    func testFinishedMeansTheLastStretchNotNinetyNinePercent() {
        let thirtyHours = 30.0 * 3600
        // 99% of 30 hours still leaves 18 minutes.
        XCTAssertFalse(AppState.ItemProgress.isFinished(time: thirtyHours * 0.99, duration: thirtyHours))
        XCTAssertTrue(AppState.ItemProgress.isFinished(time: thirtyHours - 25, duration: thirtyHours))
        // A 2-minute episode: the last 1% (1.2s), not the last 30s.
        XCTAssertFalse(AppState.ItemProgress.isFinished(time: 100, duration: 120))
        XCTAssertTrue(AppState.ItemProgress.isFinished(time: 119, duration: 120))
        XCTAssertFalse(AppState.ItemProgress.isFinished(time: 0, duration: 0))
    }

    // MARK: Resume position

    func testDownloadResumesFromNewerServerPosition() {
        // Saved locally at 2h (epoch 1000s); the server row is from later (epoch 5000s).
        let server = AppState.ItemProgress(fraction: 0.5, isFinished: false, lastUpdate: 5_000_000, currentTime: 18_000)
        XCTAssertEqual(DownloadStore.resumeTime(saved: 7_200, savedAt: 1_000, duration: 36_000, server: server), 18_000)
    }

    func testDownloadKeepsItsPositionWhenTheServerIsOlder() {
        let server = AppState.ItemProgress(fraction: 0.1, isFinished: false, lastUpdate: 500_000, currentTime: 3_600)
        XCTAssertEqual(DownloadStore.resumeTime(saved: 7_200, savedAt: 1_000, duration: 36_000, server: server), 7_200)
    }

    func testOwnWritesWithinASecondDontCountAsNewer() {
        // This Mac's progress tick updates both the download and the row.
        let server = AppState.ItemProgress(fraction: 0.2, isFinished: false, lastUpdate: 1_000_500, currentTime: 7_000)
        XCTAssertEqual(DownloadStore.resumeTime(saved: 7_200, savedAt: 1_000, duration: 36_000, server: server), 7_200)
    }

    func testServerRowWithoutTimeFallsBackToFraction() {
        let server = AppState.ItemProgress(fraction: 0.25, isFinished: false, lastUpdate: 5_000_000)
        XCTAssertEqual(DownloadStore.resumeTime(saved: 0, savedAt: 1_000, duration: 36_000, server: server), 9_000)
    }

    func testFinishedElsewhereRestartsFromTheTop() {
        let server = AppState.ItemProgress(fraction: 1, isFinished: true, lastUpdate: 5_000_000, currentTime: 36_000)
        XCTAssertEqual(DownloadStore.resumeTime(saved: 7_200, savedAt: 1_000, duration: 36_000, server: server), 0)
        XCTAssertEqual(DownloadStore.resumeTime(saved: 35_999.5, savedAt: 1_000, duration: 36_000, server: nil), 0)
    }

    // MARK: Progress merge

    func testMergeKeepsLocalRowsTheServerHasNotSeen() {
        typealias Key = AppState.ProgressKey
        let now = 10_000_000.0
        let server: [Key: AppState.ItemProgress] = [
            Key(itemID: "a", episodeID: nil): .init(fraction: 0.5, isFinished: false, lastUpdate: 2_000),
            Key(itemID: "b", episodeID: nil): .init(fraction: 0.9, isFinished: false, lastUpdate: 9_000),
        ]
        let local: [Key: AppState.ItemProgress] = [
            Key(itemID: "a", episodeID: nil): .init(fraction: 1, isFinished: true, lastUpdate: 3_000),        // optimistic mark, newer
            Key(itemID: "b", episodeID: nil): .init(fraction: 0.1, isFinished: false, lastUpdate: 1_000),     // stale
            Key(itemID: "c", episodeID: "e"): .init(fraction: 0.2, isFinished: false, lastUpdate: now - 60_000), // write in flight
            Key(itemID: "d", episodeID: nil): .init(fraction: 0.3, isFinished: false, lastUpdate: 1_000),     // reset elsewhere long ago
        ]
        let merged = AppState.mergedProgress(server: server, local: local, now: now)
        XCTAssertEqual(merged[Key(itemID: "a", episodeID: nil)]?.isFinished, true)
        XCTAssertEqual(merged[Key(itemID: "b", episodeID: nil)]?.fraction, 0.9)
        XCTAssertNotNil(merged[Key(itemID: "c", episodeID: "e")])
        XCTAssertNil(merged[Key(itemID: "d", episodeID: nil)])
    }

    // MARK: Paging

    func testItemsAreCollectedAcrossEveryPage() async throws {
        var requested: [Int] = []
        let pages = try [
            [makeItem(id: "1"), makeItem(id: "2")],
            [makeItem(id: "3"), makeItem(id: "4")],
            [makeItem(id: "5")],
        ]
        let all = try await APIClient.collectPages(pageSize: 2) { page in
            requested.append(page)
            return ItemsResponse(results: pages[page], total: nil)
        }
        XCTAssertEqual(all.map(\.id), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(requested, [0, 1, 2])
    }

    func testPagingStopsAtTheServerTotal() async throws {
        // An exact multiple of the page size: the total stops it without an empty fetch.
        var requested: [Int] = []
        let all = try await APIClient.collectPages(pageSize: 2) { page in
            requested.append(page)
            return ItemsResponse(results: try [makeItem(id: "\(page)a"), makeItem(id: "\(page)b")], total: 4)
        }
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(requested, [0, 1])
    }

    func testPagingGivesUpOnAServerThatIgnoresThePage() async throws {
        let all = try await APIClient.collectPages(pageSize: 1, maxPages: 5) { _ in
            ItemsResponse(results: try [makeItem(id: "same")], total: nil)
        }
        XCTAssertEqual(all.count, 5)
    }
}
