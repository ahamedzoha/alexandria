import SwiftUI
import AppKit

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Process-wide guard: the spacebar monitor must exist exactly once no
    /// matter how many windows create a RootView.
    @MainActor private static var keyMonitorInstalled = false

    var body: some View {
        ZStack {
            if app.isLoggedIn {
                MainView()
                    .transition(reduceMotion ? .opacity : .scale(scale: 1.02).combined(with: .opacity))
            } else {
                LoginView()
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Reduce Motion: a plain crossfade instead of the slide and scale.
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.7, dampingFraction: 0.85),
                   value: app.isLoggedIn)
        .task {
            // Persist playback position back to the server.
            player.onProgress = { id, episodeID, time, duration in
                app.reportProgress(itemID: id, episodeID: episodeID, time: time, duration: duration)
            }
            // Natural end: PlayerEngine has already reported the final
            // time == duration position (so the server sees 100%) before
            // firing this; podcasts then advance to the next unfinished
            // episode.
            // app and player live as long as the process, so strong captures
            // are fine (the weak ones here only produced compiler warnings).
            // Natural end: continue with Up Next (books too, now) unless the
            // setting is off or a sleep timer stopped here.
            player.onFinished = { _, _, continueQueue in
                guard continueQueue, app.autoPlayNextEpisodes, let next = app.queue.popNext() else { return }
                startPlayback(item: next.item, episode: next.episode, app: app, player: player)
            }
            // Logout / server switch: stop before the server changes, so the
            // final position lands on the server the item belongs to.
            app.onActiveServerWillChange = { player.stop() }
            player.onListened = { app.noteListening($0, itemID: $1) }
            installPlaybackKeys()
            if app.isLoggedIn && app.libraries.isEmpty {
                await app.loadLibraries()
                await app.flushPendingProgress()   // drain any offline-queued progress
            }
            // The 45s background sync + didBecomeActive refresh live on
            // AppState (startSyncLoop), not here — window churn can't
            // duplicate or drop them.
        }
    }

    /// Playback from the keyboard, anywhere in the window: Space plays and
    /// pauses, ←/→ skip back 15 / forward 30, ⇧←/⇧→ change chapter (see
    /// PlaybackKey for why these aren't menu shortcuts).
    ///
    /// Keys are left alone when nothing is loaded (the login screen), when
    /// Full Keyboard Access is on (there they move and press the focus; the
    /// media keys still work), and when the focused view uses them itself —
    /// typing, lists and tables, sliders.
    private func installPlaybackKeys() {
        guard !Self.keyMonitorInstalled else { return }
        Self.keyMonitorInstalled = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let action = PlaybackKey.action(keyCode: event.keyCode, modifiers: event.modifierFlags)
            else { return event }
            if PlaybackKey.belongsToFocusedView(action, responder: NSApp.keyWindow?.firstResponder) { return event }
            if NSApp.isFullKeyboardAccessEnabled { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard !player.itemID.isEmpty else { return false }
                switch action {
                case .toggle: player.toggle()
                case .skipBack: player.skip(-15)
                case .skipForward: player.skip(30)
                case .previousChapter: player.prevChapter()
                case .nextChapter: player.nextChapter()
                }
                return true
            }
            return handled ? nil : event
        }
    }
}
