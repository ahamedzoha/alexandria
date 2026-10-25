import SwiftUI

/// Home's header in miniature, for the toolbar once the real one has scrolled
/// away: the completion ring, the greeting, and the listening stats on one
/// line. Slides up and fades in as the page header leaves.
struct CompactGreeting: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visible: Bool

    var body: some View {
        // Rendered only while visible, in its own glass capsule (the toolbar
        // item's shared background is hidden): nothing — not even an empty
        // pill — before the header scrolls away, and a real backing after,
        // so it never sits bare over the content scrolling underneath.
        ZStack {
            if visible {
                capsule
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: visible)
    }

    private var capsule: some View {
        HStack(spacing: Theme.Space.s) {
            if app.libraryHasBooks {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.15), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: app.libraryCompletion)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(GreetingHeader.greeting(at: .now))
                    .font(.subheadline.weight(.semibold))
                // Symbols keep three stats inside the room left of the search
                // field; the words live in the tooltip and VoiceOver label.
                HStack(spacing: Theme.Space.s) {
                    Label(weekText, systemImage: "headphones")
                    if app.libraryHasBooks {
                        Label("\(app.finishedCount)", systemImage: "checkmark.circle")
                        Label("\(app.inProgressCount)", systemImage: "play.circle")
                    }
                }
                .labelStyle(CompactStatLabel())
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .padding(.leading, app.libraryHasBooks ? 8 : 12)
        .padding(.trailing, 12)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
        .help(fullStats)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(GreetingHeader.greeting(at: .now)). \(fullStats)")
    }

    /// This week's listening — the figure the page header leads with.
    private var weekSeconds: Double {
        app.listeningWeek().reduce(0) { $0 + $1.seconds }
    }

    private var weekText: String { weekSeconds < 60 ? "0m" : Format.duration(weekSeconds) }

    private var fullStats: String {
        let week = "\(durationString(weekSeconds) ?? "Nothing") listened this week"
        guard app.libraryHasBooks else { return week }
        return "\(week) · \(app.finishedCount) finished · \(app.inProgressCount) in progress · \(Int(app.libraryCompletion * 100))% of the library"
    }
}

/// Icon + number, tight.
private struct CompactStatLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title.monospacedDigit()
        }
    }
}

/// Five bars of the live spectrum of what's playing (AudioLevelMeter), right
/// of the search field. Real levels, not an animation: quiet passages sit
/// low, music jumps. Clicking it opens the Now Playing inspector. Under
/// Reduce Motion it holds a still shape instead of dancing.
struct LevelVisualizer: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visible: Bool

    /// Display-side smoothing: bars jump up with the music, fall back gently.
    @State private var smoother = Smoother()

    var body: some View {
        // The slot keeps its width either way, so the search field beside it
        // never shifts; the glass capsule and bars appear inside it.
        ZStack {
            if visible {
                button
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .frame(width: 44, height: 36)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: visible)
    }

    private var button: some View {
        Button { app.toggleInspector(.details) } label: {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !player.isPlaying || reduceMotion)) { _ in
                let heights = displayedHeights()
                HStack(alignment: .center, spacing: 2) {
                    ForEach(heights.indices, id: \.self) { band in
                        Capsule().frame(width: 3, height: heights[band])
                    }
                }
                .frame(width: 25, height: 18)
                .foregroundStyle(accent)
            }
            .frame(width: 44, height: 36)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("Now Playing")
        .accessibilityLabel(player.isPlaying ? "Now playing: \(player.currentTitle)" : "Paused: \(player.currentTitle)")
        .accessibilityHint("Shows the Now Playing details")
    }

    @Environment(\.colorScheme) private var colorScheme

    /// The cover's accent where it reads on the glass, else the system accent.
    private var accent: Color {
        guard let candidate = PaletteStore.shared.cached(for: player.coverURL)?.accent else { return .accentColor }
        let glass = colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92)
        return ArtworkPalette.contrastRatio(candidate, glass) >= 3 ? candidate : .accentColor
    }

    private func displayedHeights() -> [CGFloat] {
        if reduceMotion { return [6, 12, 16, 10, 6] }
        let target = player.isPlaying ? player.levelMeter.levels() : []
        return smoother.step(toward: target).map { 3 + CGFloat($0) * 15 }
    }

    final class Smoother {
        private var values = [Float](repeating: 0, count: AudioLevelMeter.bandCount)

        func step(toward target: [Float]) -> [Float] {
            for i in values.indices {
                let goal = i < target.count ? target[i] : 0
                values[i] = goal > values[i] ? values[i] + (goal - values[i]) * 0.6   // quick attack
                                             : values[i] * 0.85                       // gentle release
            }
            return values
        }
    }
}
