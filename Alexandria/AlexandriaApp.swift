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
        .commands {
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") { player.toggle() }
                Divider()
                Button("Skip Forward") { player.skip(30) }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Skip Back") { player.skip(-15) }
                    .keyboardShortcut("[", modifiers: .command)
                Divider()
                Button("Next Chapter") { player.nextChapter() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(player.chapters.isEmpty)
                Button("Previous Chapter") { player.prevChapter() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(player.chapters.isEmpty)
            }
        }

        MenuBarExtra {
            MiniPlayerView()
                .environment(app)
                .environment(player)
        } label: {
            Image(systemName: player.isPlaying ? "waveform" : "headphones")
                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
        }
        .menuBarExtraStyle(.window)
    }
}
