import SwiftUI

/// Compact player shown from the menu bar.
struct MiniPlayerView: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        VStack(spacing: 12) {
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
                        if !player.currentChapterTitle.isEmpty {
                            Text(player.currentChapterTitle)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(player.currentAuthor)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 2) {
                    Slider(
                        value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                        in: 0...max(player.duration, 1)
                    )
                    HStack {
                        Text(timeString(player.currentTime))
                        Spacer()
                        Text(timeString(player.duration))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 18) {
                    Button { player.prevChapter() } label: { Image(systemName: "backward.end.fill") }
                        .disabled(player.chapters.isEmpty)
                        .help("Previous Chapter").accessibilityLabel("Previous Chapter")
                    Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }
                        .help("Skip Back 15 Seconds").accessibilityLabel("Skip Back 15 Seconds")
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.largeTitle)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .help(player.isPlaying ? "Pause" : "Play")
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button { player.skip(30) } label: { Image(systemName: "goforward.30") }
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
                    Menu("\(player.rate, specifier: "%g")×") {
                        ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0], id: \.self) { rate in
                            Button("\(rate, specifier: "%.2f")×") { player.setRate(Float(rate)) }
                        }
                    }
                    .fixedSize()
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func timeString(_ seconds: Double) -> String {
        let x = Int(seconds.isFinite ? seconds : 0)
        let h = x / 3600, m = (x % 3600) / 60, s = x % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
