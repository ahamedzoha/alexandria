import XCTest
@testable import Alexandria

/// The pure logic behind the unified continue feature: which episode progress
/// rows are resume candidates, how books and episodes merge into one queue,
/// and what stays on the Latest Episodes shelf. All exercised through the
/// static helpers — AppState itself is not constructible in unit tests (see
/// NextEpisodeOrderingTests).
@MainActor
final class HomeContinueTests: XCTestCase {
    private func progress(_ fraction: Double, finished: Bool = false, at lastUpdate: Double) -> AppState.ItemProgress {
        AppState.ItemProgress(fraction: fraction, isFinished: finished, lastUpdate: lastUpdate)
    }

    // MARK: Resume candidates

    func testCandidatesKeepOnlyStartedUnfinishedEpisodeRows() {
        let map: [AppState.ProgressKey: AppState.ItemProgress] = [
            // Book row (episodeID nil) — never an episode candidate.
            .init(itemID: "book-1", episodeID: nil): progress(0.5, at: 900),
            // Finished episode — out.
            .init(itemID: "pod-1", episodeID: "ep-done"): progress(1.0, finished: true, at: 800),
            // Untouched episode (fraction at the floor) — out.
            .init(itemID: "pod-1", episodeID: "ep-zero"): progress(0.0005, at: 700),
            // Two real candidates.
            .init(itemID: "pod-1", episodeID: "ep-old"): progress(0.4, at: 100),
            .init(itemID: "pod-2", episodeID: "ep-new"): progress(0.2, at: 500),
        ]
        let candidates = AppState.episodeResumeCandidates(in: map)
        XCTAssertEqual(candidates.map(\.episodeID), ["ep-new", "ep-old"])
        XCTAssertEqual(candidates.map(\.itemID), ["pod-2", "pod-1"])
    }

    func testBookCandidatesSpanEveryLibrary() {
        // Book rows from any library, most recent first; episode rows,
        // finished and untouched books are left to their own surfaces.
        let map: [AppState.ProgressKey: AppState.ItemProgress] = [
            .init(itemID: "book-a", episodeID: nil): progress(0.5, at: 100),
            .init(itemID: "book-b", episodeID: nil): progress(0.1, at: 300),
            .init(itemID: "book-done", episodeID: nil): progress(1, finished: true, at: 400),
            .init(itemID: "book-new", episodeID: nil): progress(0, at: 500),
            .init(itemID: "pod", episodeID: "ep"): progress(0.5, at: 600),
        ]
        XCTAssertEqual(AppState.bookResumeCandidates(in: map), ["book-b", "book-a"])
        XCTAssertEqual(AppState.bookResumeCandidates(in: map, limit: 1), ["book-b"])
    }

    func testCandidatesRespectTheLimit() {
        var map: [AppState.ProgressKey: AppState.ItemProgress] = [:]
        for i in 0..<20 {
            map[.init(itemID: "pod", episodeID: "ep-\(i)")] = progress(0.5, at: Double(i))
        }
        let candidates = AppState.episodeResumeCandidates(in: map, limit: 5)
        XCTAssertEqual(candidates.count, 5)
        // Highest lastUpdate first.
        XCTAssertEqual(candidates.first?.episodeID, "ep-19")
        XCTAssertEqual(candidates.last?.episodeID, "ep-15")
    }

    // MARK: Cross-media merge

    func testMergedContinueOrdersAcrossMediaByLastPlayed() throws {
        let book = try makeItem(id: "book-1", title: "Anna Karenina", author: "Leo Tolstoy", duration: 3600)
        let show = try makeItem(id: "pod-1", mediaType: "podcast", title: "Lighthouse Horror")
        let episode = try makeEpisode(id: "ep-1", libraryItemId: "pod-1", title: "The Last Toys R Us", duration: 1800)

        let bookEntry = AppState.ContinueEntry.book(book, progress(0.3, at: 100))
        let episodeEntry = AppState.ContinueEntry.episode(episode, show: show, progress(0.6, at: 200))

        // Episode played more recently → episode leads.
        XCTAssertEqual(AppState.mergedContinue([bookEntry, episodeEntry]).map(\.id),
                       ["pod-1|ep-1", "book-1"])
        // And the reverse.
        let newerBook = AppState.ContinueEntry.book(book, progress(0.3, at: 300))
        XCTAssertEqual(AppState.mergedContinue([newerBook, episodeEntry]).map(\.id),
                       ["book-1", "pod-1|ep-1"])
    }

    func testContinueEntryDisplayMapping() throws {
        let book = try makeItem(id: "book-1", title: "Anna Karenina", author: "Leo Tolstoy", duration: 3600)
        let show = try makeItem(id: "pod-1", mediaType: "podcast", title: "Lighthouse Horror")
        let episode = try makeEpisode(id: "ep-1", libraryItemId: "pod-1", title: "The Last Toys R Us", duration: 1800)

        let bookEntry = AppState.ContinueEntry.book(book, progress(0.3, at: 100))
        XCTAssertEqual(bookEntry.title, "Anna Karenina")
        XCTAssertEqual(bookEntry.subtitle, "Leo Tolstoy")
        XCTAssertEqual(bookEntry.duration, 3600)
        XCTAssertNil(bookEntry.episode)

        let episodeEntry = AppState.ContinueEntry.episode(episode, show: show, progress(0.6, at: 200))
        XCTAssertEqual(episodeEntry.title, "The Last Toys R Us")
        XCTAssertEqual(episodeEntry.subtitle, "Lighthouse Horror")
        XCTAssertEqual(episodeEntry.duration, 1800)
        XCTAssertEqual(episodeEntry.episode?.id, "ep-1")
        XCTAssertEqual(episodeEntry.item.id, "pod-1")
    }

    // MARK: Latest Episodes shelf

    func testFreshEpisodesDropContinueSurfacedAndFinishedAndSortNewestFirst() throws {
        let fresh1 = try makeEpisode(id: "ep-a", libraryItemId: "pod-1", publishedAt: 3_000)
        let fresh2 = try makeEpisode(id: "ep-b", libraryItemId: "pod-1", publishedAt: 5_000)
        let started = try makeEpisode(id: "ep-c", libraryItemId: "pod-1", publishedAt: 9_000)
        let finished = try makeEpisode(id: "ep-d", libraryItemId: "pod-1", publishedAt: 8_000)
        let orphan = try makeEpisode(id: "ep-e", publishedAt: 4_000)   // no libraryItemId → kept

        let rows: [String: AppState.ItemProgress] = [
            "ep-c": progress(0.5, at: 100),
            "ep-d": progress(1.0, finished: true, at: 100),
        ]
        // ep-c is on the continue surfaces → excluded here (no duplication).
        let result = AppState.freshEpisodes(from: [fresh1, started, finished, fresh2, orphan],
                                            onContinueSurfaces: ["pod-1|ep-c"]) { _, episodeID in
            rows[episodeID]
        }
        XCTAssertEqual(result.map(\.id), ["ep-b", "ep-e", "ep-a"])
    }

    /// Regression: an in-progress episode that did NOT make the continue
    /// queue's resolution cap must stay visible on Latest Episodes — with a
    /// raw-progress exclusion it vanished from every Home surface at once.
    func testStartedEpisodeBeyondContinueCapStaysOnLatestShelf() throws {
        let cappedOut = try makeEpisode(id: "ep-13", libraryItemId: "pod-1", publishedAt: 9_000)
        let rows = ["ep-13": progress(0.4, at: 50)]
        let result = AppState.freshEpisodes(from: [cappedOut],
                                            onContinueSurfaces: []) { _, episodeID in
            rows[episodeID]
        }
        XCTAssertEqual(result.map(\.id), ["ep-13"], "capped-out started episode must surface here")
    }
}
