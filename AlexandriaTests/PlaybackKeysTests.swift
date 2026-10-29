import AppKit
import XCTest
@testable import Alexandria

/// The playback keys: which presses act, and when the focused view keeps them.
@MainActor
final class PlaybackKeysTests: XCTestCase {
    private let arrowFlags: NSEvent.ModifierFlags = [.function, .numericPad]

    func testBareKeysPlayAndSkip() {
        XCTAssertEqual(PlaybackKey.action(keyCode: PlaybackKey.space, modifiers: []), .toggle)
        XCTAssertEqual(PlaybackKey.action(keyCode: PlaybackKey.left, modifiers: arrowFlags), .skipBack)
        XCTAssertEqual(PlaybackKey.action(keyCode: PlaybackKey.right, modifiers: arrowFlags), .skipForward)
    }

    func testShiftArrowsChangeChapter() {
        XCTAssertEqual(PlaybackKey.action(keyCode: PlaybackKey.left, modifiers: arrowFlags.union(.shift)),
                       .previousChapter)
        XCTAssertEqual(PlaybackKey.action(keyCode: PlaybackKey.right, modifiers: arrowFlags.union(.shift)),
                       .nextChapter)
    }

    func testOtherModifiersBelongToSomeoneElse() {
        // ⌘← / ⌥← / ⌃← are caret, word and Space-switching keys; ⌥⌘← is the
        // Previous Chapter menu item.
        for modifiers: NSEvent.ModifierFlags in [.command, .option, .control, [.command, .option]] {
            XCTAssertNil(PlaybackKey.action(keyCode: PlaybackKey.left, modifiers: arrowFlags.union(modifiers)))
        }
        XCTAssertNil(PlaybackKey.action(keyCode: PlaybackKey.space, modifiers: .shift))
        XCTAssertNil(PlaybackKey.action(keyCode: 0, modifiers: []), "A is just a letter")
    }

    func testTypingListsAndSlidersKeepTheirKeys() {
        XCTAssertTrue(PlaybackKey.belongsToFocusedView(.skipBack, responder: NSTextView()))
        XCTAssertTrue(PlaybackKey.belongsToFocusedView(.toggle, responder: NSTextView()), "Space types a space")
        XCTAssertTrue(PlaybackKey.belongsToFocusedView(.skipForward, responder: NSTableView()))
        XCTAssertTrue(PlaybackKey.belongsToFocusedView(.nextChapter, responder: NSOutlineView()))
        XCTAssertTrue(PlaybackKey.belongsToFocusedView(.skipBack, responder: NSSlider()))
        XCTAssertFalse(PlaybackKey.belongsToFocusedView(.toggle, responder: NSTableView()),
                       "Space still plays from a list, as before")
        XCTAssertFalse(PlaybackKey.belongsToFocusedView(.skipBack, responder: nil))
    }

    // MARK: Speed and volume

    func testSpeedStepsThroughTheOfferedRates() {
        let player = PlayerEngine()
        player.setRate(1)
        player.stepRate(faster: true)
        XCTAssertEqual(player.rate, 1.25)
        player.setRate(3)
        player.stepRate(faster: true)
        XCTAssertEqual(player.rate, 3, "already the fastest")
        player.setRate(0.75)
        player.stepRate(faster: false)
        XCTAssertEqual(player.rate, 0.75, "already the slowest")
        player.setRate(1.6)   // a value from elsewhere snaps to the next offered rate
        player.stepRate(faster: true)
        XCTAssertEqual(player.rate, 1.75)
    }

    func testVolumeStaysInRange() {
        let player = PlayerEngine()
        let saved = player.userVolume
        defer { player.setVolume(saved) }
        player.setVolume(0.95)
        player.nudgeVolume(by: 0.1)
        XCTAssertEqual(player.userVolume, 1)
        player.setVolume(0.05)
        player.nudgeVolume(by: -0.1)
        XCTAssertEqual(player.userVolume, 0)
        XCTAssertNotNil(player.volumeChangedAt)
    }

    func testChapterSleepKeyArmsThenCancels() {
        let player = PlayerEngine()
        player.toggleChapterSleep()
        XCTAssertTrue(player.isSleepArmed, "with nothing loaded it arms the end of the item")
        player.toggleChapterSleep()
        XCTAssertFalse(player.isSleepArmed)
    }
}
