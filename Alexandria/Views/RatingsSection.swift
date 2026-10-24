import SwiftUI

/// Audible and Open Library ratings for a book, shared by the Now Playing
/// inspector and the detail sheet. Callers only mount it when web ratings are
/// on in Settings. Audible leads when it has the book (overall, plus its
/// story / narration split); Open Library follows on one quiet line.
struct RatingsSection: View {
    @Environment(AppState.self) private var app
    /// nil while the book's metadata is still loading.
    let query: RatingsQuery?
    var accent: Color = .accentColor

    private enum Phase: Equatable {
        case loading
        case loaded(BookRatings)
        case failed
    }

    private struct LoadKey: Hashable {
        let query: RatingsQuery?
        let store: AudibleStore
        let attempt: Int
    }

    @State private var phase = Phase.loading
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ratings").font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: LoadKey(query: query, store: app.audibleStore, attempt: attempt)) {
            guard let query else { phase = .loading; return }
            if case .loaded = phase {} else { phase = .loading }
            let ratings = await RatingsStore.shared.ratings(for: query, store: app.audibleStore)
            phase = ratings.map(Phase.loaded) ?? .failed
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking up ratings…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Text("Ratings aren't available right now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Try Again") { attempt += 1 }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        case .loaded(let ratings) where ratings.isEmpty:
            Text("No ratings found for this book.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .loaded(let ratings):
            loaded(ratings)
        }
    }

    @ViewBuilder private func loaded(_ ratings: BookRatings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let audible = ratings.audible {
                headline(audible.overall, source: "Audible", url: audible.productURL)
                if audible.story != nil || audible.narration != nil {
                    VStack(spacing: 6) {
                        if let story = audible.story { ScoreBar(label: "Story", score: story, accent: accent) }
                        if let narration = audible.narration { ScoreBar(label: "Narration", score: narration, accent: accent) }
                    }
                }
                if let openLibrary = ratings.openLibrary {
                    secondaryLine(openLibrary)
                }
            } else if let openLibrary = ratings.openLibrary {
                headline(openLibrary.score, source: "Open Library", url: openLibrary.url)
            }
        }
    }

    /// "4.0  ★★★★☆ / 433 ratings on Audible".
    private func headline(_ score: RatingScore, source: String, url: URL?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(score.average, format: .number.precision(.fractionLength(1)))
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                StarRating(value: score.average)
                HStack(spacing: 0) {
                    // Gray on the text only — on the stack it would also
                    // repaint the link, hiding that the source is clickable.
                    Text("\(score.count.formatted()) \(score.count == 1 ? "rating" : "ratings") on ")
                        .foregroundStyle(.secondary)
                    if let url {
                        Link(source, destination: url).help(url.absoluteString)
                    } else {
                        Text(source).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rated \(score.average.formatted(.number.precision(.fractionLength(1)))) out of 5 from \(score.count.formatted()) ratings on \(source)")
    }

    /// Open Library alongside Audible: one line, source as a link.
    private func secondaryLine(_ openLibrary: BookRatings.OpenLibrary) -> some View {
        HStack(spacing: 6) {
            if let url = openLibrary.url {
                Link("Open Library", destination: url).help(url.absoluteString)
            } else {
                Text("Open Library")
            }
            Spacer(minLength: 8)
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("\(openLibrary.score.average.formatted(.number.precision(.fractionLength(1)))) · \(openLibrary.score.count.formatted()) ratings")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

/// Five SF Symbol stars, half-star resolution.
private struct StarRating: View {
    let value: Double

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: symbol(for: Double(star)))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func symbol(for star: Double) -> String {
        if value >= star - 0.25 { return "star.fill" }
        if value >= star - 0.75 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// "Story ━━━━━━━━──  3.8": one facet of Audible's split rating.
private struct ScoreBar: View {
    let label: String
    let score: RatingScore
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout)
                .frame(width: 72, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(accent)
                        .frame(width: max(4, geo.size.width * min(1, score.average / 5)))
                }
            }
            .frame(height: 5)
            Text(score.average, format: .number.precision(.fractionLength(1)))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(score.average.formatted(.number.precision(.fractionLength(1)))) out of 5")
    }
}
