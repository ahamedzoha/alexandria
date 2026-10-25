import SwiftUI

/// Warm, personal home header: an editorial date eyebrow, a large-title greeting,
/// and a supporting line — on the app background (no gradient banner). The
/// library-completion ring is the single, localized spot of accent color.
struct GreetingHeader: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dateLine)
                    .font(.subheadline.weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(greeting)
                    .font(Theme.Typography.heroTitle)
                Text(app.heroContinue != nil ? "Pick up where you left off." : "Find your next listen.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Space.l)
            // Ring only when there's a library to summarize (hidden on the empty
            // state) — a 0/0 ring reads as an unfinished artifact.
            if app.libraryTotal > 0 {
                CompletionRing(progress: app.libraryCompletion,
                               finished: app.finishedCount,
                               total: app.libraryTotal)
                    .frame(width: 116, height: 116)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateLine: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var greeting: String { Self.greeting(at: .now) }

    static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

/// Trimmed-circle completion ring with animated fill (Reduce-Motion aware).
/// Recolored for the neutral app background: a subtle semantic track, an accent
/// fill, and semantic numerals (no more white-on-gradient).
struct CompletionRing: View {
    let progress: Double
    let finished: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedTo: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 9)   // adaptive track
            Circle()
                .trim(from: 0, to: animatedTo)
                .stroke(
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int(progress * 100))%")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())               // inherits .primary
                Text("\(finished)/\(total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) { animatedTo = progress }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { animatedTo = newValue }
        }
        .accessibilityElement()
        .accessibilityLabel("Library \(Int(progress * 100)) percent complete, \(finished) of \(total) finished")
    }
}

/// The continue-listening hero — the Home showcase moment. Large artwork on the
/// left; behind the whole section, a soft artwork-derived wash that bleeds
/// edge-to-edge and slides under the sidebar/toolbar via
/// `.backgroundExtensionEffect()`. Renders one `ContinueEntry` — book or
/// podcast episode — through the identical layout (eyebrow / title /
/// supporting line / progress / Resume + Details), so resuming feels the same
/// no matter the medium. Color comes from the artwork in two places only —
/// the wash and the accent — while the copy stays semantic, so the section
/// reads the same way in both appearances. Render never blocks on extraction.
/// The Resume button is the one tinted control on the page.
struct HomeHeroCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let entry: AppState.ContinueEntry
    var maxContentWidth: CGFloat = 1400
    let onPlay: () -> Void
    let onOpen: () -> Void

    @State private var palette: ArtworkPalette?

    private var coverURL: URL? { app.coverURL(itemID: entry.item.id) }

    /// The extracted palette, or the cached one on the very first frame: the
    /// hero is rebuilt every time Home reappears, and waiting for the async
    /// lookup flashed the bar and button system blue before the cover's color.
    private var currentPalette: ArtworkPalette? {
        palette ?? PaletteStore.shared.cached(for: coverURL)
    }

    // Hero copy is always semantic (`.primary`/`.secondary`), never palette
    // text. `ArtworkPalette` guarantees its text colors against the *solid*
    // artwork background, but the wash is translucent (0.45 → 0.08 in dark),
    // so what the glyphs actually sit on is mostly the window background. A
    // bright cover — say a brick red at luminance 0.17 — still reports
    // `isDark`, so the palette hands back near-black text that vanishes on the
    // dark chrome underneath. Semantic colors resolve against that real
    // backdrop and stay legible in both appearances.

    /// THE one tinted control: the palette accent, unless its contrast against
    /// the white prominent-button label drops below ~3.0 — then the app accent.
    private var resumeTint: Color {
        guard let accent = currentPalette?.accent,
              ArtworkPalette.contrastRatio(accent, .white) >= 3.0 else { return .accentColor }
        return accent
    }

    var body: some View {
        // ZStack + id swap so a hero change crossfades old/new in place —
        // opacity only, gentle .smooth spring, no slide theatrics.
        ZStack {
            heroRow
                .id(entry.id)
                .transition(.opacity)
        }
        .frame(maxWidth: maxContentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
        .background { wash }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45), value: entry.id)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45), value: palette)
        .task(id: coverURL) {
            palette = await PaletteStore.shared.palette(for: coverURL)
        }
    }

    private var heroRow: some View {
        HStack(alignment: .center, spacing: Theme.Space.l + 4) {
            Button(action: onOpen) {
                CoverArt(url: coverURL, title: entry.title)
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous)
                        .strokeBorder(Theme.hairline))
            }
            .buttonStyle(.plain)
            .hoverLift()

            VStack(alignment: .leading, spacing: 8) {
                eyebrow
                Text(entry.title)
                    .font(.title.bold())
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(entry.subtitle)
                    .font(.title3)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                progressStrip
                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(resumeTint)   // THE one tinted control
                    Button("Details", action: onOpen)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// "CONTINUE" for books; "CONTINUE · PODCAST" for episodes — the one quiet
    /// media-type cue, in the slot least likely to compete with the content.
    private var eyebrow: some View {
        Text(entry.episode == nil ? "Continue" : "Continue · Podcast")
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }

    /// Soft artwork-tinted wash behind the section. Fades toward the page below
    /// and extends under the sidebar/toolbar edges; absent (plain background)
    /// until the palette lands. Light appearance gets a much fainter wash that
    /// fades to clear — at dark-mode strength it reads as a muddy band against
    /// the bright window background.
    @ViewBuilder private var wash: some View {
        if let palette = currentPalette {
            LinearGradient(
                colors: colorScheme == .light
                    ? [palette.background.opacity(0.22), .clear]
                    : [palette.background.opacity(0.45), palette.background.opacity(0.08)],
                startPoint: .top, endPoint: .bottom
            )
            .backgroundExtensionEffect()
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Native progress bar + ticking time-remaining readout. A standard
    /// ProgressView, not a GeometryReader-measured capsule: the measured one
    /// laid out at zero width whenever Home was rebuilt and grew back into
    /// place — the bar visibly jumped on every return to Home.
    private var progressStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: min(max(entry.progress.fraction, 0), 1))
                .progressViewStyle(.linear)
                .tint(currentPalette?.accent ?? .accentColor)
                .accessibilityLabel("Progress")
                // Animate genuine progress (a sync landing), nothing else.
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: entry.progress.fraction)
            Text(remainingLabel)
                .font(.caption)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.secondary)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: remainingLabel)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(.top, 2)
    }

    private var remainingLabel: String {
        let remaining = (entry.duration ?? 0) * (1 - entry.progress.fraction)
        return durationString(remaining).map { "\($0) left" } ?? "Ready to play"
    }
}
