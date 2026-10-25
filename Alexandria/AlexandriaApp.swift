import SwiftUI

@main
struct AlexandriaApp: App {
    @State private var app = AppState()
    @State private var player = PlayerEngine()
    @StateObject private var updater = UpdaterModel()

    init() {
        // 0.5.1 and earlier persisted this override into the app's defaults,
        // where it outlived any change of mind. Clear it; ScrollBarStyle
        // applies the user's choice per launch instead.
        UserDefaults.standard.removeObject(forKey: "AppleShowScrollBars")
        ScrollBarStyle.applyAtLaunch()
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
                // ⌥⌘, not ⌘: menu equivalents run before the text field, and
                // ⌘←/⌘→ are its start/end-of-line keys (the search field).
                Button("Next Chapter") { player.nextChapter() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                    .disabled(player.chapters.isEmpty)
                Button("Previous Chapter") { player.prevChapter() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(player.chapters.isEmpty)
                Divider()
                Button(app.showNowPlayingInfo ? "Hide Info" : "Show Info") {
                    app.showNowPlayingInfo.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
                Divider()
                Toggle("Auto-Play Next Episode", isOn: Binding(
                    get: { app.autoPlayNextEpisodes },
                    set: { app.autoPlayNextEpisodes = $0 }
                ))
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }

        MenuBarExtra {
            MiniPlayerView()
                .environment(app)
                .environment(player)
        } label: {
            MenuBarIcon(isPlaying: player.isPlaying)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu bar symbol: a waveform that ripples while playing — held still under
/// Reduce Motion, where a perpetually animating icon is exactly the problem.
private struct MenuBarIcon: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: isPlaying ? "waveform" : "headphones")
            .symbolEffect(.variableColor.iterative, isActive: isPlaying && !reduceMotion)
    }
}

/// Settings ▸ Scroll bars. Slim overlay scrollers (fade in while scrolling)
/// by default; "Follow System Settings" keeps the classic bars macOS shows
/// with a mouse attached, for anyone who relies on them.
enum ScrollBarStyle: String, CaseIterable, Identifiable {
    case slim, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slim: "Slim, shown while scrolling"
        case .system: "Follow System Settings"
        }
    }

    static let defaultsKey = "scrollBarStyle"

    static var stored: ScrollBarStyle {
        ScrollBarStyle(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .slim
    }

    /// AppKit settles the scroller style at launch, so this runs from the
    /// App's init. The override goes in the argument domain — read like a
    /// `-AppleShowScrollBars` launch flag, never written to disk — so it ends
    /// with the process and can't get stuck the way 0.5.1's did.
    static func applyAtLaunch() {
        guard stored == .slim else { return }
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleShowScrollBars"] = "WhenScrolling"
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}
