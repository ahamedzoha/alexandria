import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        Group {
            if app.isLoggedIn {
                MainView()
            } else {
                LoginView()
            }
        }
        .task {
            // Persist playback position back to the server.
            player.onProgress = { id, time, duration in
                Task { await app.reportProgress(itemID: id, currentTime: time, duration: duration) }
            }
            if app.isLoggedIn && app.libraries.isEmpty {
                await app.loadLibraries()
            }
        }
    }
}
