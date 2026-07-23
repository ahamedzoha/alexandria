import XCTest
@testable import Alexandria

@MainActor
final class ProgressKeyTests: XCTestCase {
    func testSameItemAndEpisodeAreEqualAndHashAlike() {
        let a = AppState.ProgressKey(itemID: "item-1", episodeID: "ep-1")
        let b = AppState.ProgressKey(itemID: "item-1", episodeID: "ep-1")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func testNilEpisodeKeyIsDistinctFromEpisodeKey() {
        let itemLevel = AppState.ProgressKey(itemID: "item-1", episodeID: nil)
        let episodeLevel = AppState.ProgressKey(itemID: "item-1", episodeID: "ep-1")
        XCTAssertNotEqual(itemLevel, episodeLevel)
        XCTAssertEqual(Set([itemLevel, episodeLevel]).count, 2)
    }

    func testDictionaryKeepsItemAndEpisodeEntriesSeparate() {
        var map: [AppState.ProgressKey: Double] = [:]
        map[AppState.ProgressKey(itemID: "item-1", episodeID: nil)] = 0.25
        map[AppState.ProgressKey(itemID: "item-1", episodeID: "ep-1")] = 0.75
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map[AppState.ProgressKey(itemID: "item-1", episodeID: nil)], 0.25)
        XCTAssertEqual(map[AppState.ProgressKey(itemID: "item-1", episodeID: "ep-1")], 0.75)
    }

    func testDifferentItemsAreDistinct() {
        XCTAssertNotEqual(
            AppState.ProgressKey(itemID: "item-1", episodeID: nil),
            AppState.ProgressKey(itemID: "item-2", episodeID: nil)
        )
    }
}
