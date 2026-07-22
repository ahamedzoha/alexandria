import SwiftUI
import AppKit

/// NSTextField that honors a *deferred* focus request: if focus was asked for
/// while the view wasn't in a window yet (first frame, or a toolbar re-host),
/// it grabs first responder the moment it joins a window — so ⌘F never silently
/// no-ops.
final class FocusableNSTextField: NSTextField {
    var wantsFocus = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsFocus, let window {
            wantsFocus = false
            window.makeFirstResponder(self)
        }
    }
}

/// A borderless, transparent AppKit text field wrapped for SwiftUI, purpose-built
/// to live inside `ToolbarItem(placement: .principal)` as the app's search input.
///
/// Why AppKit at all? SwiftUI's `@FocusState` does **not** propagate into
/// `.toolbar`-hosted content on macOS (confirmed broken through macOS 26), so a
/// pure-SwiftUI `TextField` can never be focused by the ⌘F menu command. Driving
/// `window.makeFirstResponder(_:)` directly is the only reliable path — so the
/// field is AppKit while everything *visible* stays SwiftUI.
///
/// Why a plain `NSTextField`, not `NSSearchField`? An `NSSearchField` draws its
/// own magnifier (search-button cell) and its own clear (cancel) button. A
/// bezelless search field collapses both of those rects to x = 0, overlapping the
/// placeholder — and even when fixed they would *duplicate* the SwiftUI magnifier
/// and clear button we compose around this field. A plain `NSTextField` has
/// neither cell, so SwiftUI owns 100% of the chrome and nothing can overlap.
///
/// The field is `isBordered = false` / `isBezeled = false` / `drawsBackground =
/// false` so the single system toolbar glass capsule (macOS 26) stays the only
/// visible container — do **not** add a second background around it.
///
/// Contract:
/// - `text`         two-way bound to the query; updated live in `controlTextDidChange`.
/// - `focusTrigger` bump the integer to request first responder (wired to ⌘F).
/// - `onMoveDown` / `onMoveUp` / `onSubmit` / `onCancel` return `true` when the key
///   was *consumed* (e.g. the results dropdown handled ↑/↓/↵/esc); returning `false`
///   lets AppKit apply its default field-editor behavior for that key.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Bump this to request focus (e.g. from the ⌘F menu command).
    var focusTrigger: Int
    /// Bump this to resign first responder (esc / outside-click / after play),
    /// so a bare Space reaches the global play/pause monitor again.
    var blurTrigger: Int
    var onMoveDown: () -> Bool
    var onMoveUp: () -> Bool
    var onSubmit: () -> Bool
    var onCancel: () -> Bool

    func makeNSView(context: Context) -> FocusableNSTextField {
        let field = FocusableNSTextField()
        field.delegate = context.coordinator

        // Pure text — no search / cancel cells that could overlap the placeholder.
        field.placeholderString = placeholder
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.textColor = .labelColor
        field.alignment = .natural

        // Single line: scroll (never wrap) long queries and truncate the tail.
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.truncatesLastVisibleLine = true

        // Hug / resist compression low so the surrounding SwiftUI frame governs
        // width and the field stretches to fill its slot in the toolbar capsule.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // A plain NSTextField already exposes the text-field accessibility role;
        // the "Search books" placeholder conveys its search purpose to VoiceOver.
        field.setAccessibilitySubrole(.searchField)

        return field
    }

    func updateNSView(_ field: FocusableNSTextField, context: Context) {
        // Refresh the closures / binding the coordinator forwards to each update.
        context.coordinator.parent = self

        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        // Only write when it genuinely differs, so we never stomp the insertion
        // point while the user types (controlTextDidChange keeps them in sync).
        if field.stringValue != text {
            field.stringValue = text
        }

        // Focus request: defer one main-actor turn so first responder lands AFTER
        // SwiftUI finishes mutating the toolbar this cycle. That deferral is what
        // dodges the Sequoia/Tahoe "search field in toolbar misses focus" quirk.
        if context.coordinator.lastFocusTrigger != focusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            Task { @MainActor in
                if field.window != nil {
                    field.window?.makeFirstResponder(field)
                } else {
                    // Not in a window yet — focus as soon as it attaches
                    // (see FocusableNSTextField.viewDidMoveToWindow).
                    field.wantsFocus = true
                }
            }
        }

        if context.coordinator.lastBlurTrigger != blurTrigger {
            context.coordinator.lastBlurTrigger = blurTrigger
            Task { @MainActor in
                // Only resign if THIS field is the one being edited, so a bare
                // Space falls through to the global play/pause monitor.
                field.wantsFocus = false
                if field.currentEditor() != nil {
                    field.window?.makeFirstResponder(nil)
                }
            }
        }
    }

    /// macOS 13+: fill the SwiftUI-proposed width instead of hugging intrinsic
    /// content. Height stays at the field's fitting height so it centers cleanly
    /// within the toolbar capsule (an editable NSTextField reports an intrinsic
    /// width of -1, so this is what actually drives the horizontal stretch).
    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: FocusableNSTextField,
                      context: Context) -> CGSize? {
        let fitting = nsView.fittingSize
        let width: CGFloat
        if let proposed = proposal.width, proposed > 0, proposed < .greatestFiniteMagnitude {
            width = proposed
        } else {
            width = fitting.width
        }
        return CGSize(width: width, height: fitting.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var lastFocusTrigger: Int
        var lastBlurTrigger: Int

        init(_ parent: SearchField) {
            self.parent = parent
            self.lastFocusTrigger = parent.focusTrigger
            self.lastBlurTrigger = parent.blurTrigger
        }

        // AppKit delivers control text / editing callbacks on the main thread.
        // `MainActor.assumeIsolated` lets us touch the @MainActor AppState binding
        // and the MainView closures without tripping strict-concurrency checks.
        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            MainActor.assumeIsolated {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            MainActor.assumeIsolated {
                switch selector {
                case #selector(NSResponder.moveDown(_:)):        return parent.onMoveDown()
                case #selector(NSResponder.moveUp(_:)):          return parent.onMoveUp()
                case #selector(NSResponder.insertNewline(_:)):   return parent.onSubmit()
                case #selector(NSResponder.cancelOperation(_:)): return parent.onCancel()
                default:                                         return false
                }
            }
        }
    }
}
