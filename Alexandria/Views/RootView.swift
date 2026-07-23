import SwiftUI
import AppKit

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    /// Process-wide guard: the spacebar monitor must exist exactly once no
    /// matter how many windows create a RootView.
    @MainActor private static var spaceMonitorInstalled = false

    var body: some View {
        ZStack {
            if app.isLoggedIn {
                MainView()
                    .transition(.scale(scale: 1.02).combined(with: .opacity))
            } else {
                LoginView()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: app.isLoggedIn)
        .task {
            // Persist playback position back to the server.
            player.onProgress = { id, episodeID, time, duration in
                app.reportProgress(itemID: id, episodeID: episodeID, time: time, duration: duration)
            }
            // Natural end: PlayerEngine has already reported the final
            // time == duration position (so the server sees 100%) before
            // firing this; podcasts then advance to the next unfinished
            // episode.
            player.onFinished = { [weak app, weak player] id, episodeID in
                Task { @MainActor in
                    guard let app, let player, let episodeID, app.autoPlayNextEpisodes else { return }
                    // Cache miss (e.g. quick-play from the Home shelf): load
                    // the show's episode list before looking up the next one.
                    if app.episodes(for: id) == nil { await app.loadEpisodes(itemID: id) }
                    guard let next = app.nextEpisode(after: episodeID, in: id),
                          let item = await app.resolveItem(id: id) else { return }
                    startPlayback(item: item, episode: next, app: app, player: player)
                }
            }
            installSpacebarToggle()
            if app.isLoggedIn && app.libraries.isEmpty {
                await app.loadLibraries()
                await app.flushPendingProgress()   // drain any offline-queued progress
            }
            // The 45s background sync + didBecomeActive refresh live on
            // AppState (startSyncLoop), not here — window churn can't
            // duplicate or drop them.
        }
    }

    /// Space toggles play/pause anywhere except while editing text (so the
    /// search field still types spaces). A menu shortcut can't do this because
    /// focused buttons/controls swallow a bare Space key.
    private func installSpacebarToggle() {
        guard !Self.spaceMonitorInstalled else { return }
        Self.spaceMonitorInstalled = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
                return event
            }
            let responder = NSApp.keyWindow?.firstResponder
            if responder is NSText || responder is NSTextView { return event }  // typing in a field
            MainActor.assumeIsolated { player.toggle() }
            return nil
        }
    }
}
