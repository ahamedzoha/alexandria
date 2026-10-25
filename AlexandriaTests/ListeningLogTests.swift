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
                                     local: ["2026-10-25": ["book": 600], "2026-10-20": ["book": 60]],
                                     server: ["2026-10-25": 15, "2026-10-18": 999],   // the 18th is outside the week
                                     calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(ListeningLog.dayKey(week.first!.date, calendar: calendar), "2026-10-19")
        XCTAssertEqual(week.last?.seconds, 615, "Alexandria's 600s plus the server's 15s")
        XCTAssertEqual(week[1].seconds, 60)
        XCTAssertEqual(week.map(\.seconds).reduce(0, +), 675)
    }

    func testDaysListTheirBooksMostListenedFirst() {
        let week = ListeningLog.week(endingAt: date(25),
                                     local: ["2026-10-25": ["short": 120, "long": 900, "": 30]],
                                     server: ["2026-10-25": 400],
                                     serverItems: ["2026-10-25": ["phone": 400]],
                                     calendar: calendar)
        XCTAssertEqual(week.last?.itemIDs, ["long", "phone", "short"], "unknown-book seconds count but show no cover")
        XCTAssertEqual(week.last?.seconds, 1450)
        XCTAssertEqual(ListeningLog.mostListened(in: week, local: ["2026-10-25": ["short": 120, "long": 900]],
                                                 serverItems: ["2026-10-25": ["phone": 400]], calendar: calendar),
                       "long")
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
        log.add(5, itemID: "a", on: date(25))
        log.add(5, itemID: "a", on: date(25))
        log.add(3, itemID: "b", on: date(25))
        log.add(0, itemID: "a", on: date(24))
        let today = ListeningLog.dayKey(date(25))
        XCTAssertEqual(log.days[today], ["a": 10, "b": 3])
        XCTAssertEqual(log.totals[today], 13)
        XCTAssertNil(log.days[ListeningLog.dayKey(date(24))], "nothing played, nothing recorded")
        XCTAssertEqual(ListeningLog(defaults: defaults).days[today], ["a": 10, "b": 3])
    }

    func testVersionOneLogMigratesWithoutBooks() {
        let suite = "ListeningLogTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["2026-10-25": 180.0], forKey: "listeningLog")
        let log = ListeningLog(defaults: defaults)
        XCTAssertEqual(log.totals["2026-10-25"], 180)
        XCTAssertEqual(log.days["2026-10-25"], ["": 180])
    }
}
