import XCTest
@testable import Alexandria

@MainActor
final class FormatTests: XCTestCase {
    func testDurationBoundaries() {
        XCTAssertEqual(Format.duration(0), "<1m")
        XCTAssertEqual(Format.duration(59), "<1m")
        XCTAssertEqual(Format.duration(60), "1m")
        XCTAssertEqual(Format.duration(3600), "1h")
        XCTAssertEqual(Format.duration(3660), "1h 1m")     // 61 minutes
        XCTAssertEqual(Format.duration(11520), "3h 12m")   // 3h 12m
    }

    func testTimestampBoundaries() {
        XCTAssertEqual(Format.timestamp(0), "0:00")
        XCTAssertEqual(Format.timestamp(59), "0:59")
        XCTAssertEqual(Format.timestamp(3660), "1:01:00")   // 61 minutes
        XCTAssertEqual(Format.timestamp(11520), "3:12:00")  // 3h 12m
    }

    func testTimestampGuardsNonFiniteInput() {
        XCTAssertEqual(Format.timestamp(.infinity), "0:00")
        XCTAssertEqual(Format.timestamp(.nan), "0:00")
    }

    func testRelativeDateIsNonEmpty() {
        let text = Format.relativeDate(Date(timeIntervalSinceNow: -3 * 86_400))
        XCTAssertFalse(text.isEmpty)
    }
}
