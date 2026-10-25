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

    // MARK: Track layout

    private func track(_ index: Int, start: Double?, duration: Double?) -> PlaybackInfo.AudioTrack {
        PlaybackInfo.AudioTrack(index: index, startOffset: start, duration: duration, title: nil,
                                contentUrl: "/api/items/b/file/\(index)", mimeType: nil)
    }

    func testTrackOffsetsUseTheServersWhenSent() {
        let tracks = [track(0, start: 0, duration: 100), track(1, start: 100, duration: 50)]
        XCTAssertEqual(PlayerEngine.trackOffsets(tracks), [0, 100])
    }

    func testAMissingOffsetStartsWhereThePreviousTrackEnds() {
        // Falling back to the previous offset alone put tracks 2 and 3 at 100.
        let tracks = [track(0, start: 0, duration: 100), track(1, start: 100, duration: 50),
                      track(2, start: nil, duration: 75), track(3, start: nil, duration: nil)]
        XCTAssertEqual(PlayerEngine.trackOffsets(tracks), [0, 100, 150, 225])
    }

    func testTrackIndexIsTheLastTrackStartingAtOrBeforeTheTime() {
        let offsets: [Double] = [0, 100, 150]
        XCTAssertEqual(PlayerEngine.trackIndex(at: 0, offsets: offsets), 0)
        XCTAssertEqual(PlayerEngine.trackIndex(at: 99.9, offsets: offsets), 0)
        XCTAssertEqual(PlayerEngine.trackIndex(at: 100, offsets: offsets), 1)
        XCTAssertEqual(PlayerEngine.trackIndex(at: 5_000, offsets: offsets), 2)
    }

    // MARK: Track URLs

    func testRelativeTracksJoinTheServerWithoutATokenInTheURL() {
        let url = PlayerEngine.trackURL("/api/items/b/file/1", serverURL: "https://abs.example/", token: "secret")
        XCTAssertEqual(url?.absoluteString, "https://abs.example/api/items/b/file/1")
    }

    func testHLSTracksCarryTheTokenOnce() {
        let url = PlayerEngine.trackURL("/hls/s1/output.m3u8", serverURL: "https://abs.example", token: "secret")
        XCTAssertEqual(url?.absoluteString, "https://abs.example/hls/s1/output.m3u8?token=secret")
        let again = PlayerEngine.trackURL("/hls/s1/output.m3u8?token=secret", serverURL: "https://abs.example",
                                          token: "secret")
        XCTAssertEqual(again?.absoluteString, "https://abs.example/hls/s1/output.m3u8?token=secret")
    }

    func testHLSIsRecognisedBehindASubpathProxy() {
        // The server lives at /abs; content paths are relative to it.
        let url = PlayerEngine.trackURL("/hls/s1/output.m3u8", serverURL: "https://host.example/abs/",
                                        token: "secret")
        XCTAssertEqual(url?.absoluteString, "https://host.example/abs/hls/s1/output.m3u8?token=secret")
        let file = PlayerEngine.trackURL("/api/items/b/file/1", serverURL: "https://host.example/abs",
                                         token: "secret")
        XCTAssertEqual(file?.absoluteString, "https://host.example/abs/api/items/b/file/1")
    }

    func testLocalFilesPassThrough() {
        let url = PlayerEngine.trackURL("file:///tmp/0.mp3", serverURL: "https://abs.example", token: "secret")
        XCTAssertEqual(url?.absoluteString, "file:///tmp/0.mp3")
    }

    // MARK: Chapters

    func testTheChapterUnderThePlayheadIncludesTheHalfSecondBeforeIt() {
        let player = PlayerEngine()
        player.chapters = PlayerEngine.chapters(from: [.init(start: 0, end: 600, title: "One"),
                                                       .init(start: 600, end: 1200, title: "Two")],
                                                duration: 1200)
        player.currentTime = 300
        XCTAssertEqual(player.currentChapterIndex, 0)
        player.currentTime = 599.6   // a seek to 600 can land a hair early
        XCTAssertEqual(player.currentChapterTitle, "Two")
        player.currentTime = 1199
        XCTAssertEqual(player.currentChapterIndex, 1)
    }

    func testPlayWithNothingLoadedStaysStopped() {
        let player = PlayerEngine()
        player.play()
        XCTAssertFalse(player.isPlaying)
        player.toggle()
        XCTAssertFalse(player.isPlaying)
    }
}
