import AppKit

/// What a key press does to playback.
enum PlaybackAction: Equatable {
    case toggle
    case skipBack, skipForward
    case previousChapter, nextChapter
}

/// The keys the window-wide monitor (RootView) turns into playback, and when
/// it must leave them alone. A monitor rather than menu key equivalents:
/// menu equivalents run before the focused view, so they would steal the
/// caret keys from the search field and the arrow keys from lists.
enum PlaybackKey {
    static let space: UInt16 = 49
    static let left: UInt16 = 123
    static let right: UInt16 = 124

    /// The action for this key and modifiers; nil passes the event on.
    /// Arrow keys carry the function/numeric-pad flags, which don't count.
    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> PlaybackAction? {
        let held = modifiers.intersection([.command, .option, .control, .shift])
        switch (keyCode, held) {
        case (space, []): return .toggle
        case (left, []): return .skipBack
        case (right, []): return .skipForward
        case (left, .shift): return .previousChapter
        case (right, .shift): return .nextChapter
        default: return nil
        }
    }

    /// The focused view has its own use for this key: typing (Space and the
    /// arrows move the caret), lists and tables (the arrows move the
    /// selection), and sliders.
    static func belongsToFocusedView(_ action: PlaybackAction, responder: NSResponder?) -> Bool {
        if responder is NSText { return true }
        guard action != .toggle else { return false }
        return responder is NSTableView || responder is NSCollectionView || responder is NSSlider
    }
}
