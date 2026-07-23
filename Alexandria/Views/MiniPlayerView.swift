import SwiftUI
import AppKit

/// Compact player shown from the menu bar. Shares the NowPlayingBar design
/// language: artwork, palette-tinted progress, the same transport verbs.
struct MiniPlayerView: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.openWindow) private var openWindow
    @State private var palette: ArtworkPalette?
    @State private var scrubTime: Double?
    @State private var backSkips = 0
    @State private var forwardSkips = 0
    @State private var showSpeedPopover = false

    var body: some View {
        VStack(spacing: 12) {
            header
            Divider()
            if player.currentTitle.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "headphones")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Nothing playing")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                nowPlaying
            }
        }
        .padding(16)
        .frame(width: 300)
        .task(id: player.coverURL) {
            palette = await PaletteStore.shared.palette(for: player.coverURL)
        }
    }

    /// Artwork-derived tint for the progress track and small live elements
    /// only — never whole surfaces. Falls back to the app accent.
    private var accent: Color { palette?.accent ?? .accentColor }

    @ViewBuilder private var nowPlaying: some View {
        HStack(spacing: 12) {
            RemoteImage(url: player.coverURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } fallback: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(player.currentTitle).font(.headline).lineLimit(2)
                if let live = scrubbingSubtitle {
                    // Live scrub target: chapter (books) / episode (podcasts).
                    Text(live)
                        .font(.caption).foregroundStyle(accent).lineLimit(1)
                } else if !player.currentChapterTitle.isEmpty {
                    Text(player.currentChapterTitle)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(player.currentAuthor)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }

        VStack(spacing: 4) {
            PlaybackScrubber(
                currentTime: player.currentTime,
                duration: player.duration,
                accent: accent,
                compact: true,
                scrubTime: $scrubTime
            ) { player.seek(to: $0) }
            HStack {
                Text(Format.timestamp(scrubTime ?? player.currentTime))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: Format.timestamp(scrubTime ?? player.currentTime))
                Spacer()
                Text(Format.timestamp(player.duration))
                    .contentTransition(.numericText())
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 18) {
            Button { player.prevChapter() } label: { Image(systemName: "backward.end.fill") }
                .disabled(player.chapters.isEmpty)
                .help("Previous Chapter").accessibilityLabel("Previous Chapter")
            Button { backSkips += 1; player.skip(-15) } label: {
                Image(systemName: "gobackward.15")
                    .symbolEffect(.bounce, value: backSkips)
            }
            .help("Skip Back 15 Seconds").accessibilityLabel("Skip Back 15 Seconds")
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.largeTitle)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(player.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { forwardSkips += 1; player.skip(30) } label: {
                Image(systemName: "goforward.30")
                    .symbolEffect(.bounce, value: forwardSkips)
            }
            .help("Skip Forward 30 Seconds").accessibilityLabel("Skip Forward 30 Seconds")
            Button { player.nextChapter() } label: { Image(systemName: "forward.end.fill") }
                .disabled(player.chapters.isEmpty)
                .help("Next Chapter").accessibilityLabel("Next Chapter")
        }
        .buttonStyle(.plain)
        .font(.title3)

        HStack {
            Text("Speed").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { showSpeedPopover.toggle() } label: {
                Text("\(player.rate, specifier: "%g")×")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: player.rate)
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Playback speed")
            .popover(isPresented: $showSpeedPopover) {
                SpeedPopover(accent: accent)
            }
        }
    }

    private var scrubbingSubtitle: String? {
        guard let t = scrubTime else { return nil }
        return player.chapterTitle(at: t) ?? player.currentTitle
    }

    private var header: some View {
        HStack {
            Label("Alexandria", systemImage: "books.vertical.fill")
                .font(.headline)
                .foregroundStyle(.tint)
            Spacer()
            Button("Open Library") { openLibrary() }
                .buttonStyle(.link)
                .font(.callout)
        }
    }

    private func openLibrary() {
        // openWindow reuses the main window when one exists and creates it
        // when none does (the menu-bar player can outlive every window).
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
