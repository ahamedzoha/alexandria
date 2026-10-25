import XCTest
@testable import Alexandria

/// Episode order: the list sort, where a show-level Play starts, and what
/// auto-play picks next. (Pure functions on EpisodeOrder, so no AppState.)
final class NextEpisodeOrderingTests: XCTestCase {
    /// Episodes 1…5 published a day apart.
    private func show() throws -> [PodcastEpisode] {
        try (1...5).map { try makeEpisode(id: "ep\($0)", publishedAt: $0 * 86_400_000) }
    }

    func testListSortsEitherWay() throws {
        let episodes = try show().shuffled()
        XCTAssertEqual(EpisodeOrder.oldestFirst.sorted(episodes).map(\.id), ["ep1", "ep2", "ep3", "ep4", "ep5"])
        XCTAssertEqual(EpisodeOrder.newestFirst.sorted(episodes).map(\.id), ["ep5", "ep4", "ep3", "ep2", "ep1"])
    }

    func testSerialShowsDefaultToOldestFirst() {
        XCTAssertEqual(EpisodeOrder.defaultOrder(podcastType: "serial"), .oldestFirst)
        XCTAssertEqual(EpisodeOrder.defaultOrder(podcastType: "episodic"), .newestFirst)
        XCTAssertEqual(EpisodeOrder.defaultOrder(podcastType: nil), .newestFirst)
    }

    func testOldestFirstStartsAtTheBeginningOfAnUnstartedShow() throws {
        let start = EpisodeOrder.oldestFirst.startingEpisode(in: try show()) { _ in false }
        XCTAssertEqual(start?.id, "ep1", "listening straight through starts at episode 1, not the newest")
    }

    func testNewestFirstStartsAtTheNewest() throws {
        XCTAssertEqual(EpisodeOrder.newestFirst.startingEpisode(in: try show()) { _ in false }?.id, "ep5")
    }

    func testEitherOrderContinuesAfterTheLastFinished() throws {
        let finished: Set = ["ep1", "ep2"]
        for order in EpisodeOrder.allCases {
            XCTAssertEqual(order.startingEpisode(in: try show()) { finished.contains($0.id) }?.id, "ep3")
        }
    }

    func testOldestFirstSkipsAPlayedFirstEpisode() throws {
        // Only a later episode was finished out of order: continue after it.
        let start = EpisodeOrder.oldestFirst.startingEpisode(in: try show()) { $0.id == "ep3" }
        XCTAssertEqual(start?.id, "ep4")
    }

    func testAutoPlayGoesToTheNextNewerUnfinishedEpisode() throws {
        let next = EpisodeOrder.nextEpisode(after: "ep2", in: try show()) { $0.id == "ep3" }
        XCTAssertEqual(next?.id, "ep4", "skips the finished ep3")
        XCTAssertNil(EpisodeOrder.nextEpisode(after: "ep5", in: try show()) { _ in false }, "nothing after the newest")
    }
}
