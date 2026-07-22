import SwiftUI

struct StatsView: View {
    @Environment(AppState.self) private var app
    @State private var loading = true

    private var stats: LibraryStats? { app.stats }

    var body: some View {
        ScrollView {
            if let stats {
                VStack(spacing: 28) {
                    tileRow(stats)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 20)], spacing: 20) {
                        genresCard(stats)
                        authorsCard(stats)
                        longestCard(stats)
                        largestCard(stats)
                    }
                }
                .padding(28)
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            } else {
                ContentUnavailableView("No stats", systemImage: "chart.bar",
                                       description: Text("Could not load library statistics."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            loading = true
            await app.loadStats()
            loading = false
        }
    }

    // MARK: Tiles

    private func tileRow(_ s: LibraryStats) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)], spacing: 16) {
            tile("books.vertical.fill", "\(s.totalItems ?? app.items.count)", "Items")
            tile("clock.fill", hours(s.totalDuration), "Overall Hours")
            tile("person.2.fill", "\(s.totalAuthors ?? 0)", "Authors")
            tile("externaldrive.fill", gb(s.totalSize), "Size (GB)")
            tile("music.note.list", "\(s.numAudioTracks ?? 0)", "Audio Tracks")
        }
    }

    private func tile(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(.tint)
                Text(value).font(.system(.title, design: .rounded).weight(.bold))
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }

    // MARK: Cards

    private func genresCard(_ s: LibraryStats) -> some View {
        let items = (s.genresWithCount ?? []).sorted { $0.value > $1.value }.prefix(5)
        let total = Double(s.totalItems ?? app.items.count)
        return chartCard("Top Genres") {
            ForEach(Array(items.enumerated()), id: \.offset) { _, g in
                let pct = total > 0 ? Double(g.value) / total : 0
                barRow(label: g.label, trailing: "\(Int(pct * 100))%", fraction: pct)
            }
        }
    }

    private func authorsCard(_ s: LibraryStats) -> some View {
        let items = (s.authorsWithCount ?? []).sorted { $0.value > $1.value }.prefix(10)
        let maxVal = Double(items.map(\.value).max() ?? 1)
        return chartCard("Top Authors") {
            ForEach(Array(items.enumerated()), id: \.offset) { _, a in
                barRow(label: a.label, trailing: "\(a.value)",
                       fraction: maxVal > 0 ? Double(a.value) / maxVal : 0)
            }
        }
    }

    private func longestCard(_ s: LibraryStats) -> some View {
        let items = (s.longestItems ?? []).sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }.prefix(6)
        let maxVal = items.map { $0.duration ?? 0 }.max() ?? 1
        return chartCard("Longest Items (hrs)") {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let h = (item.duration ?? 0) / 3600
                barRow(label: item.title ?? "—", trailing: String(format: "%.1f", h),
                       fraction: maxVal > 0 ? (item.duration ?? 0) / maxVal : 0)
            }
        }
    }

    private func largestCard(_ s: LibraryStats) -> some View {
        let items = (s.largestItems ?? []).sorted { ($0.size ?? 0) > ($1.size ?? 0) }.prefix(6)
        let maxVal = items.map { $0.size ?? 0 }.max() ?? 1
        return chartCard("Largest Items") {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                barRow(label: item.title ?? "—",
                       trailing: gb(item.size) + " GB",
                       fraction: maxVal > 0 ? (item.size ?? 0) / maxVal : 0)
            }
        }
    }

    private func chartCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.bold())
            VStack(spacing: 12) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }

    private func barRow(label: String, trailing: String, fraction: Double) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.callout).lineLimit(1)
                Spacer()
                Text(trailing).font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: Formatting

    private func hours(_ seconds: Double?) -> String {
        guard let seconds else { return "0" }
        return "\(Int(seconds / 3600))"
    }
    private func gb(_ bytes: Double?) -> String {
        guard let bytes else { return "0" }
        return String(format: "%.1f", bytes / 1_073_741_824)
    }
}
