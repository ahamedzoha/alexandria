import XCTest
@testable import Alexandria

/// PlayerEngine logic that runs without loading audio.
@MainActor
final class PlayerEngineTests: XCTestCase {
    func testSleepTimerCountsWallClockTimeAtAnySpeed() {
        // At 2× the playback ticks arrive every 0.25s of wall time. Counting
        // each as half a second used to end a 30-minute timer after 15.
        let player = PlayerEngine()
        player.setSleepTimer(minutes: 30)
        var clock: TimeInterval = 1_000
        player.advanceSleepTimer(now: clock)   // first tick only starts the clock
        for _ in 0..<(29 * 60 * 4) {           // 29 minutes of 2× ticks
            clock += 0.25
            player.advanceSleepTimer(now: clock)
        }
        XCTAssertTrue(player.isSleepArmed, "still armed after 29 wall-clock minutes")
        for _ in 0..<(60 * 4 + 1) {
            clock += 0.25
            player.advanceSleepTimer(now: clock)
        }
        XCTAssertFalse(player.isSleepArmed, "fires at 30 minutes")
    }

    func testSleepTimerIgnoresLongGapsBetweenTicks() {
        let player = PlayerEngine()
        player.setSleepTimer(minutes: 5)
        player.advanceSleepTimer(now: 0)
        player.advanceSleepTimer(now: 600)   // a 10-minute stall counts as one second
        XCTAssertEqual(player.sleepRemainingSeconds ?? 0, 299, accuracy: 0.001)
    }

    func testChapterEndsAreFilledInWhenMissing() {
        let raw = [
            PlaybackInfo.Chapter(start: 0, end: 0, title: "One"),        // zero end
            PlaybackInfo.Chapter(start: 600, end: nil, title: "Two"),    // missing end
            PlaybackInfo.Chapter(start: 1200, end: 1500, title: nil),    // fine; no title
        ]
        let chapters = PlayerEngine.chapters(from: raw, duration: 1800)
        XCTAssertEqual(chapters.map(\.end), [600, 1200, 1500])
        XCTAssertEqual(chapters.last?.title, "Chapter 3")
        // Last chapter without an end runs to the end of the book.
        XCTAssertEqual(PlayerEngine.chapters(from: [.init(start: 0, end: nil, title: "Only")], duration: 900).first?.end, 900)
    }

    func testPlayWithNothingLoadedStaysStopped() {
        let player = PlayerEngine()
        player.play()
        XCTAssertFalse(player.isPlaying)
        player.toggle()
        XCTAssertFalse(player.isPlaying)
    }
}
