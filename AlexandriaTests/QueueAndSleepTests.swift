import XCTest
@testable import Alexandria

@MainActor
final class QueueAndSleepTests: XCTestCase {
    // MARK: Automatic fill

    func testPodcastQueueIsTheFollowingUnplayedEpisodesOldestFirst() throws {
        let episodes = try (1...6).map { try makeEpisode(id: "ep\($0)", publishedAt: $0 * 86_400_000) }.shuffled()
        let following = PlaybackQueue.followingEpisodes(after: "ep2", in: episodes) { $0.id == "ep4" }
        XCTAssertEqual(following.map(\.id), ["ep3", "ep5", "ep6"])
    }

    func testBookQueueIsTheRestOfTheSeriesInReadingOrder() throws {
        let library = try [
            makeItem(id: "dt3", title: "The Waste Lands", series: "The Dark Tower #3"),
            makeItem(id: "dt1", title: "The Gunslinger", series: "The Dark Tower #1"),
            makeItem(id: "dt2", title: "The Drawing of the Three", series: "The Dark Tower #2"),
            makeItem(id: "dt4", title: "Wizard and Glass", series: "The Dark Tower #4"),
            makeItem(id: "other", title: "It", series: "Standalone #1"),
        ]
        let current = library.first { $0.id == "dt2" }!
        let following = PlaybackQueue.followingBooks(after: current, in: library) { $0.id == "dt3" }
        XCTAssertEqual(following.map(\.id), ["dt4"], "finished dt3 skipped; earlier books and other series excluded")
    }

    func testBookWithoutASeriesNumberQueuesNothing() throws {
        let book = try makeItem(id: "solo", title: "Solo")
        XCTAssertTrue(PlaybackQueue.followingBooks(after: book, in: [book]) { _ in false }.isEmpty)
    }

    // MARK: Queue operations

    private func entry(_ id: String) throws -> QueueEntry {
        try XCTUnwrap(QueueEntry(item: try makeItem(id: id, title: id), episode: nil))
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: Persistence

    func testQueueSurvivesARelaunch() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = PlaybackQueue(directory: dir)
        first.bind(to: "server-a")
        first.started("now", automatic: [try entry("auto")], source: "The Dark Tower")
        first.playNext(try entry("mine"))

        let relaunched = PlaybackQueue(directory: dir)
        relaunched.bind(to: "server-a")
        XCTAssertEqual(relaunched.manual.map(\.id), ["mine"])
        XCTAssertEqual(relaunched.automatic.map(\.id), ["auto"])
        XCTAssertEqual(relaunched.automaticSource, "The Dark Tower")
    }

    func testEachServerKeepsItsOwnQueue() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let queue = PlaybackQueue(directory: dir)
        queue.bind(to: "a")
        queue.playLater(try entry("from-a"))
        queue.bind(to: "b")
        XCTAssertTrue(queue.isEmpty)
        queue.playLater(try entry("from-b"))
        queue.bind(to: "a")
        XCTAssertEqual(queue.manual.map(\.id), ["from-a"])
    }

    func testForgettingAServerDeletesItsQueue() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let queue = PlaybackQueue(directory: dir)
        queue.bind(to: "gone")
        queue.playLater(try entry("x"))
        queue.forget(serverID: "gone")
        XCTAssertTrue(queue.isEmpty)
        let again = PlaybackQueue(directory: dir)
        again.bind(to: "gone")
        XCTAssertTrue(again.isEmpty)
    }

    func testPodcastShowsAreNotQueueable() throws {
        XCTAssertNil(QueueEntry(item: try makeItem(id: "show", mediaType: "podcast", title: "Show"), episode: nil))
    }

    func testInsertMovesEntriesIntoPlaceWithoutDuplicates() throws {
        let queue = PlaybackQueue()
        queue.started("now", automatic: [try entry("auto")], source: nil)
        queue.playLater(try entry("a"))
        queue.playLater(try entry("b"))
        queue.playLater(try entry("c"))
        // Drag "a" and the automatic entry down to just before "c".
        queue.insert([try entry("a"), try entry("auto")], at: 2)
        XCTAssertEqual(queue.manual.map(\.id), ["b", "a", "auto", "c"])
        XCTAssertTrue(queue.automatic.isEmpty)
    }

    func testRemovingASelection() throws {
        let queue = PlaybackQueue()
        queue.started("now", automatic: [try entry("x"), try entry("y")], source: nil)
        queue.playLater(try entry("m"))
        queue.remove(["m", "y"])
        XCTAssertEqual(queue.upNext.map(\.id), ["x"])
        queue.clearAll()
        XCTAssertTrue(queue.isEmpty)
    }

    func testManualEntriesPlayBeforeAutomaticOnes() throws {
        let queue = PlaybackQueue()
        queue.started("now", automatic: [try entry("auto1"), try entry("auto2")], source: "Series")
        queue.playLater(try entry("later"))
        queue.playNext(try entry("next"))
        XCTAssertEqual(queue.upNext.map(\.id), ["next", "later", "auto1", "auto2"])
        XCTAssertEqual(queue.popNext()?.id, "next")
        XCTAssertEqual(queue.popNext()?.id, "later")
        XCTAssertEqual(queue.popNext()?.id, "auto1")
    }

    func testQueueingSomethingTwiceMovesItInsteadOfDuplicating() throws {
        let queue = PlaybackQueue()
        queue.started("now", automatic: [try entry("a"), try entry("b")], source: nil)
        queue.playNext(try entry("b"))
        XCTAssertEqual(queue.upNext.map(\.id), ["b", "a"])
    }

    func testStartingAQueuedItemTakesItOffAndRefillsAroundIt() throws {
        let queue = PlaybackQueue()
        queue.playLater(try entry("x"))
        queue.playLater(try entry("y"))
        queue.started("x", automatic: [try entry("y"), try entry("z")], source: "Show")
        XCTAssertEqual(queue.manual.map(\.id), ["y"])
        XCTAssertEqual(queue.automatic.map(\.id), ["z"], "already queued by hand, so not repeated")
        XCTAssertEqual(queue.automaticSource, "Show")
    }

    // MARK: Sleep options

    private let chapters = [
        PlayerEngine.Chapter(id: 0, start: 0, end: 600, title: "One"),
        PlayerEngine.Chapter(id: 1, start: 600, end: 1200, title: "Two"),
        PlayerEngine.Chapter(id: 2, start: 1200, end: 1800, title: "Three"),
        PlayerEngine.Chapter(id: 3, start: 1800, end: 2400, title: "Four"),
        PlayerEngine.Chapter(id: 4, start: 2400, end: 3000, title: "Five"),
    ]

    func testBookOptionsAreTheNextChapterEndsAndTheBookEnd() {
        let options = PlayerEngine.sleepOptions(chapters: chapters, currentTime: 900, duration: 3000,
                                                rate: 1, isEpisode: false, next: nil)
        XCTAssertEqual(options.map(\.title),
                       ["End of This Chapter", "End of “Three”", "End of “Four”", "End of This Book"])
        XCTAssertEqual(options[0].timer, .at(1200))
        XCTAssertEqual(options[0].remaining, 300)
        XCTAssertEqual(options.last?.timer, .itemEnds(1))
    }

    func testDistancesAccountForPlaybackSpeed() {
        let options = PlayerEngine.sleepOptions(chapters: chapters, currentTime: 900, duration: 3000,
                                                rate: 2, isEpisode: false, next: nil)
        XCTAssertEqual(options[0].remaining, 150, "300s of audio at 2x is 150s of real time")
    }

    func testEpisodeOptionsReachIntoUpNext() {
        let options = PlayerEngine.sleepOptions(chapters: [], currentTime: 600, duration: 1500,
                                                rate: 1, isEpisode: true, next: ("Episode 18", 1680))
        XCTAssertEqual(options.map(\.title), ["End of This Episode", "End of “Episode 18”"])
        XCTAssertEqual(options[1].timer, .itemEnds(2))
        XCTAssertEqual(options[1].remaining, 900 + 1680)
    }

    // MARK: Stop points

    func testChapterStopPausesAtTheBoundary() {
        let player = PlayerEngine()
        player.setSleep(.at(1200))
        player.currentTime = 1100
        player.advanceSleepTimer(now: 0)
        XCTAssertTrue(player.isSleepArmed)
        player.currentTime = 1199.9
        player.advanceSleepTimer(now: 1)
        XCTAssertFalse(player.isSleepArmed, "fired at the chapter end")
    }

    func testSeekingWellPastTheStopPointDisarmsIt() {
        let player = PlayerEngine()
        player.setSleep(.at(1200))
        player.currentTime = 2000
        player.advanceSleepTimer(now: 0)
        XCTAssertFalse(player.isSleepArmed)
    }

    func testRemainingTimeForContentStops() {
        let player = PlayerEngine()
        player.duration = 3000
        player.currentTime = 900
        player.setSleep(.at(1200))
        XCTAssertEqual(player.sleepRemainingSeconds, 300)
        player.setSleep(.itemEnds(1))
        XCTAssertEqual(player.sleepRemainingSeconds, 2100)
        player.setSleep(.itemEnds(2))
        XCTAssertNil(player.sleepRemainingSeconds, "depends on the next item's length")
    }
}
