import SwiftUI
import Charts

struct StatsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loading = true
    @State private var appear = false
    @State private var selectedItem: LibraryItem?

    private var stats: LibraryStats? { app.stats }

    private let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .cyan]

    var body: some View {
        ScrollView {
            if let stats {
                VStack(spacing: 26) {
                    hero(stats)
                    tiles(stats)
                    ViewThatFits(in: .horizontal) {
                        Grid(horizontalSpacing: 20, verticalSpacing: 20) {
                            GridRow {
                                genresCard(stats).frame(maxWidth: .infinity, maxHeight: .infinity)
                                authorsCard(stats).frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        VStack(spacing: 20) { genresCard(stats); authorsCard(stats) }
                    }
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
            ItemDetailView(item: item).frame(width: 560, height: 680)
        }
        .task {
            loading = true
            await app.loadStats()
            loading = false
            appear = true
        }
    }

    // MARK: Hero

    private func hero(_ s: LibraryStats) -> some View {
        let hours = Int((s.totalDuration ?? 0) / 3600)
        let days = Double(hours) / 24
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Library").font(.largeTitle.bold())
                Text("\(s.totalItems ?? app.items.count) books · \(hours) hours of listening — that's \(String(format: "%.0f", days)) days nonstop 🎧")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 12)
            serverLogo
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.5), .pink.opacity(0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14)))
    }

    private var serverLogo: some View {
        let host = app.activeServer?.name ?? "audiobookshelf"
        return VStack(spacing: 8) {
            Image(systemName: "headphones.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            Text(host)
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(.white.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.35)))
        }
        .fixedSize()
    }

    // MARK: Tiles

    private func tiles(_ s: LibraryStats) -> some View {
        HStack(spacing: 16) {
            tile("books.vertical.fill", "\(s.totalItems ?? app.items.count)", "Items", [.blue, .cyan])
            tile("clock.fill", "\(Int((s.totalDuration ?? 0) / 3600))", "Overall Hours", [.orange, .pink])
            tile("person.2.fill", "\(s.totalAuthors ?? 0)", "Authors", [.purple, .indigo])
            tile("internaldrive.fill", gb(s.totalSize), "Size (GB)", [.teal, .green])
            tile("music.note.list", "\(s.numAudioTracks ?? 0)", "Audio Tracks", [.pink, .purple])
        }
    }

    private func tile(_ icon: String, _ value: String, _ label: String, _ colors: [Color]) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .shadow(color: colors[0].opacity(0.5), radius: 8, y: 3)
            Text(value).font(.system(.title, design: .rounded).weight(.bold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06)))
        .scaleEffect((appear || reduceMotion) ? 1 : 0.9)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: appear)
    }

    // MARK: Genres donut

    private func genresCard(_ s: LibraryStats) -> some View {
        let genres = Array((s.genresWithCount ?? []).sorted { $0.value > $1.value }.prefix(6))
        let top = genres.first
        let total = Double(genres.reduce(0) { $0 + $1.value })
        return card("Top Genres", icon: "theatermasks", fillHeight: true) {
            HStack(spacing: 20) {
                ZStack {
                    Chart(Array(genres.enumerated()), id: \.offset) { index, g in
                        SectorMark(angle: .value("Books", g.value),
                                   innerRadius: .ratio(0.72), angularInset: 2)
                            .cornerRadius(4)
                            .foregroundStyle(palette[index % palette.count])
                    }
                    .frame(width: 230, height: 230)
                    if let top, total > 0 {
                        VStack(spacing: 2) {
                            Text("\(Int(Double(top.value) / total * 100))%")
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                            Text("top genre").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(genres.enumerated()), id: \.offset) { index, g in
                        HStack(spacing: 8) {
                            Circle().fill(palette[index % palette.count]).frame(width: 10, height: 10)
                            Text(g.label).font(.callout).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(g.value)").font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Author ranked bars

    private func authorsCard(_ s: LibraryStats) -> some View {
        let authors = Array((s.authorsWithCount ?? []).sorted { $0.value > $1.value }.prefix(8))
        let maxVal = Double(authors.map(\.value).max() ?? 1)
        return card("Top Authors", icon: "person.3", fillHeight: true) {
            VStack(spacing: 10) {
                ForEach(Array(authors.enumerated()), id: \.offset) { index, a in
                    AuthorBar(rank: index + 1, name: a.label, value: a.value,
                              fraction: maxVal > 0 ? Double(a.value) / maxVal : 0,
                              animate: appear) {
                        app.showGroup(kind: .authors, value: a.label)
                    }
                }
            }
        }
    }

    // MARK: Spotlight cover strips

    private func spotlight(_ title: String, systemImage: String,
                           items: [LibraryStats.StatItem], value: @escaping (LibraryStats.StatItem) -> String) -> some View {
        card(title, icon: systemImage) {
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
    }

    // MARK: Card shell

    private func card<Content: View>(_ title: String, icon: String, fillHeight: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.title3.bold())
                .labelStyle(.titleAndIcon)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }

    // MARK: Formatting

    private func gb(_ bytes: Double?) -> String {
        guard let bytes else { return "0" }
        return String(format: "%.1f", bytes / 1_073_741_824)
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
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(6)
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous).strokeBorder(Theme.hairline))
                .hoverLift(cornerRadius: Theme.Radius.cover)

                Text(title).font(.caption).lineLimit(1).frame(width: 100, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
    }
}

// MARK: - Animated author bar

private struct AuthorBar: View {
    let rank: Int
    let name: String
    let value: Int
    let fraction: Double
    let animate: Bool
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    rankView.frame(width: 24, alignment: .leading)
                    Text(name).font(.callout.weight(hovering ? .semibold : .regular)).lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                        .opacity(hovering ? 1 : 0)
                    Spacer(minLength: 4)
                    Text("\(value)").font(.callout.monospacedDigit().weight(.bold)).foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.1))
                        Capsule()
                            .fill(LinearGradient(colors: barColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: (animate || reduceMotion) ? max(4, geo.size.width * fraction) : 0)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(value) books")
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8).delay(Double(rank) * 0.05), value: animate)
    }

    @ViewBuilder private var rankView: some View {
        switch rank {
        case 1: medal(.yellow)
        case 2: medal(Color(white: 0.75))
        case 3: medal(.brown)
        default: Text("\(rank)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private func medal(_ color: Color) -> some View {
        Image(systemName: "medal.fill")
            .font(.callout)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
    }

    private var barColors: [Color] {
        switch rank {
        case 1: return [.yellow, .orange]
        case 2: return [.gray, .white.opacity(0.6)]
        case 3: return [.orange, .brown]
        default: return [.accentColor, .accentColor.opacity(0.6)]
        }
    }
}
