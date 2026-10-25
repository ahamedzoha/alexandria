import XCTest
@testable import Alexandria

@MainActor
final class ListeningLogTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 20))!
    }

    func testWeekIsSevenDaysEndingTodayWithBothSourcesAdded() {
        let week = ListeningLog.week(endingAt: date(25),
                                     local: ["2026-10-25": 600, "2026-10-20": 60],
                                     server: ["2026-10-25": 15, "2026-10-18": 999],   // the 18th is outside the week
                                     calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(ListeningLog.dayKey(week.first!.date, calendar: calendar), "2026-10-19")
        XCTAssertEqual(week.last?.seconds, 615, "Alexandria's 600s plus the server's 15s")
        XCTAssertEqual(week[1].seconds, 60)
        XCTAssertEqual(week.map(\.seconds).reduce(0, +), 675)
    }

    func testStreakCountsConsecutiveDays() {
        let days = ["2026-10-25": 300.0, "2026-10-24": 120, "2026-10-23": 61, "2026-10-21": 900]
        XCTAssertEqual(ListeningLog.streak(endingAt: date(25), local: days, server: [:], calendar: calendar), 3)
    }

    func testStreakStillStandsBeforeTodaysFirstListen() {
        let days = ["2026-10-24": 600.0, "2026-10-23": 600]
        XCTAssertEqual(ListeningLog.streak(endingAt: date(25), local: days, server: [:], calendar: calendar), 2)
    }

    func testUnderAMinuteDoesNotCount() {
        XCTAssertEqual(ListeningLog.streak(endingAt: date(25), local: ["2026-10-25": 30], server: [:],
                                           calendar: calendar), 0)
    }

    func testAddingAccumulatesAndPersists() {
        let suite = "ListeningLogTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = ListeningLog(defaults: defaults)
        log.add(5, on: date(25))
        log.add(5, on: date(25))
        log.add(0, on: date(24))
        XCTAssertEqual(log.days[ListeningLog.dayKey(date(25))], 10)
        XCTAssertNil(log.days[ListeningLog.dayKey(date(24))], "nothing played, nothing recorded")
        XCTAssertEqual(ListeningLog(defaults: defaults).days[ListeningLog.dayKey(date(25))], 10)
    }
}
