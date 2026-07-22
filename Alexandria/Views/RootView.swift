import SwiftUI
import AppKit

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @State private var spaceMonitorInstalled = false

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
            player.onProgress = { id, time, duration in
                Task { await app.reportProgress(itemID: id, currentTime: time, duration: duration) }
            }
            installSpacebarToggle()
            if app.isLoggedIn && app.libraries.isEmpty {
                await app.loadLibraries()
                await app.flushPendingProgress()   // drain any offline-queued progress
            }
            // Keep progress fresh from other devices while the app stays open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if app.isLoggedIn { await app.syncNow() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if app.isLoggedIn { Task { await app.syncNow() } }
        }
    }

    /// Space toggles play/pause anywhere except while editing text (so the
    /// search field still types spaces). A menu shortcut can't do this because
    /// focused buttons/controls swallow a bare Space key.
    private func installSpacebarToggle() {
        guard !spaceMonitorInstalled else { return }
        spaceMonitorInstalled = true
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
