import SwiftUI

struct NowPlayingBar: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        if player.currentTitle.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 14) {
                RemoteImage(url: player.coverURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } fallback: {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(player.currentChapterTitle.isEmpty ? player.currentAuthor : player.currentChapterTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 180, alignment: .leading)

                Button { player.prevChapter() } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.plain)
                .disabled(player.chapters.isEmpty)
                .help("Previous Chapter")
                .accessibilityLabel("Previous Chapter")

                Button { player.skip(-15) } label: {
                    Image(systemName: "gobackward.15")
                }
                .buttonStyle(.plain)
                .help("Skip Back 15 Seconds")
                .accessibilityLabel("Skip Back 15 Seconds")

                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(player.isPlaying ? "Pause" : "Play")
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button { player.skip(30) } label: {
                    Image(systemName: "goforward.30")
                }
                .buttonStyle(.plain)
                .help("Skip Forward 30 Seconds")
                .accessibilityLabel("Skip Forward 30 Seconds")

                Button { player.nextChapter() } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.plain)
                .disabled(player.chapters.isEmpty)
                .help("Next Chapter")
                .accessibilityLabel("Next Chapter")

                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .frame(minWidth: 120)

                Text(timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                sleepMenu

                Menu {
                    ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0], id: \.self) { rate in
                        Button("\(rate, specifier: "%.2f")×") { player.setRate(Float(rate)) }
                    }
                } label: {
                    Text("\(player.rate, specifier: "%g")×")
                        .font(.caption.bold())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    @ViewBuilder private var sleepMenu: some View {
        Menu {
            if player.isSleepArmed {
                Button("Turn Off", systemImage: "moon.slash") { player.cancelSleepTimer() }
                Divider()
            }
            ForEach([5, 10, 15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) min") { player.setSleepTimer(minutes: minutes) }
            }
            Button("End of Chapter") { player.setSleepEndOfChapter() }
                .disabled(player.chapters.isEmpty)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: player.isSleepArmed ? "moon.fill" : "moon")
                    .symbolEffect(.pulse, isActive: player.isSleepArmed)
                if let remaining = player.sleepRemainingSeconds {
                    Text(sleepLabel(remaining)).font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(player.isSleepArmed ? Color.accentColor : .secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sleep timer")
    }

    private func sleepLabel(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var timeLabel: String {
        func fmt(_ s: Double) -> String {
            let x = Int(s.isFinite ? s : 0)
            let h = x / 3600, m = (x % 3600) / 60, sec = x % 60
            return h > 0
                ? String(format: "%d:%02d:%02d", h, m, sec)
                : String(format: "%d:%02d", m, sec)
        }
        return "\(fmt(player.currentTime)) / \(fmt(player.duration))"
    }
}
