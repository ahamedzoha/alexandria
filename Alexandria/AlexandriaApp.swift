import SwiftUI

@main
struct AlexandriaApp: App {
    @State private var app = AppState()
    @State private var player = PlayerEngine()
    @StateObject private var updater = UpdaterModel()

    init() {
        // Use slim overlay scrollers (appear while scrolling, then fade) even
        // when a mouse is attached — otherwise macOS renders wide legacy
        // scroller bars that fight the sheet/card design. Per-app override of
        // the system "Show scroll bars" preference; SwiftUI's
        // .scrollIndicators(.hidden) is ignored in legacy-scroller mode.
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    var body: some Scene {
        // Identified so the menu-bar mini player can reopen it via
        // openWindow(id: "main") after the last window closes.
        WindowGroup(id: "main") {
            RootView()
                .environment(app)
                .environment(player)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
            CommandGroup(after: .textEditing) {
                Button("Find") { app.focusSearchRequested = true }
                    .keyboardShortcut("f", modifiers: .command)
            }
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
                Divider()
                Toggle("Auto-Play Next Episode", isOn: Binding(
                    get: { app.autoPlayNextEpisodes },
                    set: { app.autoPlayNextEpisodes = $0 }
                ))
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
