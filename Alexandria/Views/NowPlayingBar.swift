import SwiftUI
import AppKit

struct NowPlayingBar: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette: ArtworkPalette?
    @State private var scrubTime: Double?
    @State private var backSkips = 0
    @State private var forwardSkips = 0
    @State private var showSpeedPopover = false
    @State private var showSleepPopover = false

    var body: some View {
        if player.currentTitle.isEmpty {
            EmptyView()
        } else {
            ViewThatFits(in: .horizontal) {
                fullBar
                compactBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .navGlass()
            .shadow(color: .black.opacity(0.08), radius: 5, y: 1)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .task(id: player.coverURL) {
                palette = await PaletteStore.shared.palette(for: player.coverURL)
            }
        }
    }

    /// Artwork-derived tint for the progress track and small live elements
    /// only — never the whole bar. Falls back to the app accent.
    private var accent: Color { palette?.accent ?? .accentColor }

    private var fullBar: some View {
        HStack(spacing: 14) {
            artwork
            titleBlock.frame(width: 180, alignment: .leading)
            transport
            scrubber
            sleepButton
            speedButton
        }
    }

    private var compactBar: some View {
        HStack(spacing: 12) {
            artwork
            titleBlock.frame(minWidth: 100, alignment: .leading).layoutPriority(1)
            transport
            scrubber
        }
    }

    private var artwork: some View {
        RemoteImage(url: player.coverURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } fallback: {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(player.currentTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Group {
                if let live = scrubbingSubtitle {
                    // Live scrub target: chapter (books) / episode (podcasts).
                    Text(live).foregroundStyle(accent)
                } else {
                    Text(player.currentChapterTitle.isEmpty ? player.currentAuthor : player.currentChapterTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
    }

    private var scrubbingSubtitle: String? {
        guard let t = scrubTime else { return nil }
        return player.chapterTitle(at: t) ?? player.currentTitle
    }

    private var transport: some View {
        HStack(spacing: 14) {
            Button { player.prevChapter() } label: { Image(systemName: "backward.end.fill") }
                .buttonStyle(.plain).disabled(player.chapters.isEmpty)
                .help("Previous Chapter").accessibilityLabel("Previous Chapter")

            Button { backSkips += 1; player.skip(-15) } label: {
                Image(systemName: "gobackward.15")
                    .symbolEffect(.bounce, value: backSkips)
            }
            .buttonStyle(.plain)
            .help("Skip Back 15 Seconds").accessibilityLabel("Skip Back 15 Seconds")

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(player.isPlaying ? "Pause" : "Play").accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button { forwardSkips += 1; player.skip(30) } label: {
                Image(systemName: "goforward.30")
                    .symbolEffect(.bounce, value: forwardSkips)
            }
            .buttonStyle(.plain)
            .help("Skip Forward 30 Seconds").accessibilityLabel("Skip Forward 30 Seconds")

            Button { player.nextChapter() } label: { Image(systemName: "forward.end.fill") }
                .buttonStyle(.plain).disabled(player.chapters.isEmpty)
                .help("Next Chapter").accessibilityLabel("Next Chapter")
        }
        .fixedSize()
    }

    private var scrubber: some View {
        HStack(spacing: 8) {
            PlaybackScrubber(
                currentTime: player.currentTime,
                duration: player.duration,
                accent: accent,
                scrubTime: $scrubTime
            ) { player.seek(to: $0) }
                .frame(minWidth: 100)
            Text(timeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: timeLabel)
                .fixedSize()
        }
    }

    private var speedButton: some View {
        Button { showSpeedPopover.toggle() } label: {
            Text("\(player.rate, specifier: "%g")×")
                .font(.caption.bold().monospacedDigit())
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

    private var sleepButton: some View {
        Button { showSleepPopover.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: player.isSleepArmed ? "moon.fill" : "moon")
                    .symbolEffect(.pulse, isActive: player.isSleepArmed && !reduceMotion)
                if let remaining = player.sleepRemainingSeconds {
                    Text(sleepLabel(remaining))
                        .font(.caption2.monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.25), value: sleepLabel(remaining))
                }
            }
            .foregroundStyle(player.isSleepArmed ? accent : .secondary)
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Sleep timer")
        .popover(isPresented: $showSleepPopover) {
            SleepTimerPopover(accent: accent)
        }
    }

    private func sleepLabel(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var timeLabel: String {
        "\(Format.timestamp(scrubTime ?? player.currentTime)) / \(Format.timestamp(player.duration))"
    }
}

extension PlayerEngine {
    /// Chapter title at an arbitrary position — used for live scrub feedback.
    func chapterTitle(at time: Double) -> String? {
        chapters.last(where: { time + 0.5 >= $0.start })?.title
    }
}

/// Two-speed scrubber (Castro-style). A plain drag maps the pointer position
/// directly onto the timeline (coarse); holding Option scales movement down to
/// 1/20th for fine ± adjustment. While dragging, `scrubTime` carries the
/// preview position so the owner can show live time and chapter feedback; the
/// seek fires once, on release.
struct PlaybackScrubber: View {
    let currentTime: Double
    let duration: Double
    let accent: Color
    var compact = false
    @Binding var scrubTime: Double?
    let onSeek: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var lastDragX: CGFloat?

    private static let fineScale = 0.05
    private static let knobSize: CGFloat = 11

    private var isScrubbing: Bool { scrubTime != nil }
    private var trackHeight: CGFloat { isScrubbing ? 7 : (compact ? 4 : 5) }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let shown = min(max(scrubTime ?? currentTime, 0), max(duration, 1))
            let fraction = duration > 0 ? shown / duration : 0

            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                    .frame(height: trackHeight)
                Capsule().fill(accent)
                    .frame(width: max(trackHeight, fraction * width), height: trackHeight)
                knob
                    .offset(x: min(max(0, fraction * width - Self.knobSize / 2), width - Self.knobSize))
                    .opacity(hovering || isScrubbing ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: 16)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isScrubbing)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(Text(Format.timestamp(currentTime)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(currentTime + 30, duration))
            case .decrement: onSeek(max(currentTime - 15, 0))
            @unknown default: break
            }
        }
    }

    private var knob: some View {
        Circle()
            .fill(.background)
            .overlay(Circle().strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.1), radius: 1.5, y: 0.5)
            .frame(width: Self.knobSize, height: Self.knobSize)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0 else { return }
                let fine = NSEvent.modifierFlags.contains(.option)
                if fine, let last = lastDragX {
                    let delta = Double((value.location.x - last) / width) * duration * Self.fineScale
                    scrubTime = clamp((scrubTime ?? currentTime) + delta)
                } else if fine {
                    scrubTime = scrubTime ?? currentTime
                } else {
                    scrubTime = clamp(Double(value.location.x / width) * duration)
                }
                lastDragX = value.location.x
            }
            .onEnded { _ in
                if let target = scrubTime { onSeek(target) }
                scrubTime = nil
                lastDragX = nil
            }
    }

    private func clamp(_ t: Double) -> Double { min(max(t, 0), duration) }
}

/// Playback-speed picker, popover-presented per HIG (anchored, fixed width).
struct SpeedPopover: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss
    let accent: Color

    private static let rates: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback Speed")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Self.rates, id: \.self) { rate in
                    if abs(Double(player.rate) - rate) < 0.01 {
                        rateButton(rate)
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                    } else {
                        rateButton(rate)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func rateButton(_ rate: Double) -> some View {
        Button {
            player.setRate(Float(rate))
            dismiss()
        } label: {
            Text("\(rate, specifier: "%g")×")
                .monospacedDigit()
                .frame(maxWidth: .infinity)
        }
    }
}

/// Sleep-timer options, popover-presented per HIG (anchored, fixed width).
struct SleepTimerPopover: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss
    let accent: Color

    private static let minuteOptions = [5, 10, 15, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sleep Timer")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let remaining = player.sleepRemainingSeconds {
                    Text(remainingLabel(remaining))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(accent)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy(duration: 0.25), value: remainingLabel(remaining))
                } else if player.isSleepArmed {
                    Text("End of chapter")
                        .font(.subheadline)
                        .foregroundStyle(accent)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Self.minuteOptions, id: \.self) { minutes in
                    Button {
                        player.setSleepTimer(minutes: minutes)
                        dismiss()
                    } label: {
                        Text("\(minutes) min").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Button {
                player.setSleepEndOfChapter()
                dismiss()
            } label: {
                Text("End of Chapter").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(player.chapters.isEmpty)

            if player.isSleepArmed {
                Button {
                    player.cancelSleepTimer()
                    dismiss()
                } label: {
                    Label("Turn Off", systemImage: "moon.slash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func remainingLabel(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
