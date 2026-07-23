import SwiftUI

/// The one surface licensed for expressive data visualization: a full-bleed
/// listening chart as the hero, with Fantastical-style linked stat rows
/// beneath — hairline-separated sections on the plain window background, no
/// floating cards. Color comes from the most-listened artwork's palette
/// (system accent until it resolves), never a stock gradient.
struct StatsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loading = true
    @State private var appear = false
    @State private var selectedItem: LibraryItem?
    @State private var selectedBarID: String?
    @State private var artworkPalette: ArtworkPalette?

    private var stats: LibraryStats? { app.stats }

    var body: some View {
        ScrollView {
            if let stats {
                VStack(alignment: .leading, spacing: 26) {
                    header(stats)
                    statStrip(stats)
                    Divider()
                    listeningSection
                    Divider()
                    ViewThatFits(in: .horizontal) {
                        Grid(horizontalSpacing: 40, verticalSpacing: 26) {
                            GridRow {
                                genresSection(stats).frame(maxWidth: .infinity, alignment: .topLeading)
                                authorsSection(stats).frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                        VStack(alignment: .leading, spacing: 26) {
                            genresSection(stats)
                            authorsSection(stats)
                        }
                    }
                    Divider()
                    spotlight("Longest Listens", systemImage: "hourglass",
                              items: (stats.longestItems ?? []).sorted { ($0.duration ?? 0) > ($1.duration ?? 0) },
                              value: { durationString($0.duration) ?? "" })
                    spotlight("Biggest Files", systemImage: "internaldrive",
                              items: (stats.largestItems ?? []).sorted { ($0.size ?? 0) > ($1.size ?? 0) },
                              value: { (sizeString($0.size) ?? "") })
                }
                .padding(28)
                .frame(maxWidth: 1150)
                .frame(maxWidth: .infinity)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.35), value: appear)
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            } else {
                ContentUnavailableView("No stats", systemImage: "chart.bar",
                                       description: Text("Could not load library statistics."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item)
                .frame(width: item.isPodcast ? 640 : 560, height: item.isPodcast ? 760 : 680)
        }
        .task {
            loading = true
            await app.loadStats()
            loading = false
            appear = true
        }
        .task(id: heroCoverURL) {
            if artworkPalette == nil, let cached = PaletteStore.shared.cached(for: heroCoverURL) {
                artworkPalette = cached
            }
            artworkPalette = await PaletteStore.shared.palette(for: heroCoverURL)
        }
    }

    // MARK: Listening data (fraction × duration over loaded items — the only
    // per-item listening data the server exposes here; nothing invented).

    private var listenEntries: [ListeningEntry] {
        Array(
            app.items.compactMap { item -> ListeningEntry? in
                guard let p = app.progress(itemID: item.id) else { return nil }
                let fraction = p.isFinished ? 1 : p.fraction
                let seconds = fraction * (item.duration ?? 0)
                guard seconds >= 60 else { return nil }
                return ListeningEntry(id: item.id, title: item.title, author: item.author,
                                      hours: seconds / 3600, fraction: min(1, fraction),
                                      coverURL: app.coverURL(itemID: item.id))
            }
            .sorted { $0.hours > $1.hours }
            .prefix(10)
        )
    }

    private var maxListenHours: Double { max(listenEntries.map(\.hours).max() ?? 1, 0.001) }

    /// The whole page shares one hue family, seeded by the most-listened
    /// item's artwork accent when the palette has resolved.
    private var ramp: IntensityRamp { IntensityRamp(base: artworkPalette?.accent ?? .accentColor) }

    private var heroCoverURL: URL? { listenEntries.first?.coverURL }

    private func rampColor(_ intensity: Double) -> Color {
        ramp.color(intensity, dark: scheme == .dark)
    }

    private func staggerDelay(_ index: Int) -> Double {
        reduceMotion ? 0 : min(0.35, Double(index) * 0.045)
    }

    // MARK: Header

    private func header(_ s: LibraryStats) -> some View {
        let hours = Int((s.totalDuration ?? 0) / 3600)
        let days = Int((Double(hours) / 24).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            Text(app.activeServer?.name ?? "Library")
                .font(.subheadline.weight(.medium))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text("Your Library")
                .font(.largeTitle.bold())
            Text("\(s.totalItems ?? app.items.count) books · \(hours) hours of audio — about \(days) days end to end.")
                .font(.title3)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Stat strip

    private func statStrip(_ s: LibraryStats) -> some View {
        HStack(spacing: 0) {
            stat("\(s.totalItems ?? app.items.count)", "Items")
            statDivider
            stat("\(Int((s.totalDuration ?? 0) / 3600))", "Hours of audio")
            statDivider
            stat(listenedText, "Hours listened")
            statDivider
            stat("\(s.totalAuthors ?? 0)", "Authors")
            statDivider
            stat(sizeString(s.totalSize) ?? "—", "On disk")
        }
        .animation(reduceMotion ? nil : .snappy, value: listenedText)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var statDivider: some View {
        Divider().frame(height: 36)
    }

    private var listenedText: String {
        let h = app.listenedHours
        return String(format: h < 10 ? "%.1f" : "%.0f", h)
    }

    // MARK: Listening hero

    private var listeningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Listening", systemImage: "waveform")
                    .font(.title3.bold())
                Spacer(minLength: 16)
                listeningReadout
            }
            if listenEntries.isEmpty {
                emptyListening
            } else {
                ListeningBarChart(entries: listenEntries, ramp: ramp, selection: $selectedBarID)
                    .frame(height: 260)
                VStack(spacing: 0) {
                    ForEach(Array(listenEntries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        ListenRankRow(rank: index + 1, entry: entry,
                                      color: rampColor(entry.hours / maxListenHours),
                                      highlighted: selectedBarID == entry.id,
                                      onHover: { inside in
                                          if inside {
                                              selectedBarID = entry.id
                                          } else if selectedBarID == entry.id {
                                              selectedBarID = nil
                                          }
                                      },
                                      onTap: { selectedItem = app.item(byID: entry.id) })
                    }
                }
                .animation(.smooth(duration: 0.2), value: selectedBarID)
            }
        }
        .animation(.smooth(duration: 0.5), value: artworkPalette)
    }

    /// Linked readout in the section header: the hovered bar's title + hours,
    /// else the overall listened total.
    private var listeningReadout: some View {
        Group {
            if let id = selectedBarID, let entry = listenEntries.first(where: { $0.id == id }) {
                Text("\(entry.title) · \(listeningHoursLabel(entry.hours))")
            } else {
                Text("\(listeningHoursLabel(app.listenedHours)) listened")
            }
        }
        .font(.callout.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .contentTransition(.numericText())
        .animation(.smooth(duration: 0.2), value: selectedBarID)
    }

    private var emptyListening: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Nothing listened yet")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Press play on a book and your hours will chart here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    // MARK: Genres / Authors

    private func genresSection(_ s: LibraryStats) -> some View {
        let genres = Array((s.genresWithCount ?? []).sorted { $0.value > $1.value }.prefix(8))
        let maxVal = Double(genres.map(\.value).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Genres", systemImage: "books.vertical")
                .font(.title3.bold())
            if genres.isEmpty {
                Text("No genre data.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(genres.enumerated()), id: \.offset) { index, genre in
                        if index > 0 { Divider() }
                        ProportionRow(label: genre.label, value: genre.value,
                                      fraction: maxVal > 0 ? Double(genre.value) / maxVal : 0,
                                      color: rampColor(maxVal > 0 ? Double(genre.value) / maxVal : 0),
                                      delay: staggerDelay(index))
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: artworkPalette)
    }

    private func authorsSection(_ s: LibraryStats) -> some View {
        let authors = Array((s.authorsWithCount ?? []).sorted { $0.value > $1.value }.prefix(8))
        let maxVal = Double(authors.map(\.value).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Authors", systemImage: "person.2")
                .font(.title3.bold())
            if authors.isEmpty {
                Text("No author data.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(authors.enumerated()), id: \.offset) { index, author in
                        if index > 0 { Divider() }
                        ProportionRow(label: author.label, value: author.value,
                                      fraction: maxVal > 0 ? Double(author.value) / maxVal : 0,
                                      color: rampColor(maxVal > 0 ? Double(author.value) / maxVal : 0),
                                      delay: staggerDelay(index)) {
                            app.showGroup(kind: .authors, value: author.label)
                        }
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: artworkPalette)
    }

    // MARK: Spotlight cover strips

    private func spotlight(_ title: String, systemImage: String,
                           items: [LibraryStats.StatItem], value: @escaping (LibraryStats.StatItem) -> String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(items.prefix(10).enumerated()), id: \.offset) { _, item in
                        SpotlightCoverCard(
                            coverURL: item.id.flatMap { app.coverURL(itemID: $0) },
                            title: item.title ?? "—",
                            value: value(item)
                        ) {
                            if let match = app.items.first(where: { $0.id == item.id }) {
                                selectedItem = match
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Spotlight cover (clickable)

private struct SpotlightCoverCard: View {
    let coverURL: URL?
    let title: String
    let value: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: coverURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } fallback: {
                    RoundedRectangle(cornerRadius: Theme.Radius.cover).fill(.quaternary)
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Text(value)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .padding(6)
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous).strokeBorder(.separator))
                .hoverLift()

                Text(title).font(.caption).lineLimit(1).frame(width: 100, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
    }
}
