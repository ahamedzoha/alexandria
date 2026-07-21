import SwiftUI

@main
struct AlexandriaApp: App {
    @State private var app = AppState()
    @State private var player = PlayerEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(player)
                .frame(minWidth: 900, minHeight: 600)
        }

        MenuBarExtra {
            MiniPlayerView()
                .environment(app)
                .environment(player)
        } label: {
            Image(systemName: player.isPlaying ? "waveform" : "headphones")
        }
        .menuBarExtraStyle(.window)
    }
}
