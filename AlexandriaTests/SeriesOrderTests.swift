import XCTest
@testable import Alexandria

@MainActor
final class SeriesOrderTests: XCTestCase {
    func testSequenceParsesFromMinifiedSeriesName() throws {
        let book = try makeItem(id: "dt7", title: "The Dark Tower", series: "The Dark Tower #7")
        XCTAssertEqual(book.seriesSequence(in: "The Dark Tower"), 7)
        XCTAssertNil(book.seriesSequence(in: "Some Other Series"))
    }

    func testSequencePicksTheRequestedSeriesFromSeveral() throws {
        let book = try makeItem(id: "b", title: "Crossover", series: "Mid-World #4.5, The Dark Tower #8")
        XCTAssertEqual(book.seriesSequence(in: "Mid-World"), 4.5)
        XCTAssertEqual(book.seriesSequence(in: "The Dark Tower"), 8)
    }

    func testSeriesOrderedSortsBySequenceNotTitle() throws {
        let books = try [
            makeItem(id: "7", title: "The Dark Tower", series: "The Dark Tower #7"),
            makeItem(id: "1", title: "The Gunslinger", series: "The Dark Tower #1"),
            makeItem(id: "4.5", title: "The Wind Through the Keyhole", series: "The Dark Tower #4.5"),
            makeItem(id: "2", title: "The Drawing of the Three", series: "The Dark Tower #2"),
            makeItem(id: "none", title: "A Companion", series: "The Dark Tower"),
        ]
        XCTAssertEqual(AppState.seriesOrdered(books, series: "The Dark Tower").map(\.id),
                       ["1", "2", "4.5", "7", "none"])
    }

    func testSeriesGroupSwitchesToSeriesOrderAndBack() {
        let app = AppState()
        app.showGroup(kind: .series, value: "The Dark Tower")
        XCTAssertEqual(app.sort, .seriesOrder)
        XCTAssertTrue(app.availableSorts.contains(.seriesOrder))

        app.clearGroup()
        XCTAssertEqual(app.sort, .title)
        XCTAssertFalse(app.availableSorts.contains(.seriesOrder))
    }
}
