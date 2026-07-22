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
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(app.heroContinueItem != nil ? "Pick up where you left off." : "Find your next listen.")
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

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
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

/// The featured "Continue" card — one-tap resume of the most-recent in-progress book.
struct HomeHeroCard: View {
    @Environment(AppState.self) private var app
    let item: LibraryItem
    let progress: AppState.ItemProgress?
    let onPlay: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            Button(action: onOpen) {
                CoverArt(url: app.coverURL(itemID: item.id), title: item.title)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous)
                        .strokeBorder(Theme.hairline))
            }
            .buttonStyle(.plain)
            .hoverLift(cornerRadius: Theme.Radius.cover)

            VStack(alignment: .leading, spacing: 8) {
                Text("CONTINUE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(item.title).font(.title2.bold()).lineLimit(2)
                Text(item.author).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                progressStrip
                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.accentColor)
                    Button("Details", action: onOpen)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.l)
        .contentCard(cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .combine)
    }

    private var progressStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * (progress?.fraction ?? 0)))
                }
            }
            .frame(height: 6)
            Text(remainingLabel).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var remainingLabel: String {
        let remaining = (item.duration ?? 0) * (1 - (progress?.fraction ?? 0))
        return durationString(remaining).map { "\($0) left" } ?? "Ready to play"
    }
}
