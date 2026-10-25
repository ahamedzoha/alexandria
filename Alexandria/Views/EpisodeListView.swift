import SwiftUI

/// Episode list for the podcast detail sheet: header with count + filter menu,
/// season group headers when the feed provides seasons, newest-first rows.
struct EpisodeListView: View {
    @Environment(AppState.self) private var app
    let item: LibraryItem

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case unplayed = "Unplayed"
        case downloaded = "Downloaded"
        case inProgress = "In Progress"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all

    var body: some View {
        if let episodes = app.episodes(for: item.id) {
            if episodes.isEmpty {
                ContentUnavailableView(
                    "No Episodes",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Episodes will appear here once the server has them.")
                )
                .frame(maxWidth: .infinity)
            } else {
                list(episodes)
            }
        } else if app.episodesLoadFailed.contains(item.id) {
            ContentUnavailableView {
                Label("Couldn't Load Episodes", systemImage: "wifi.exclamationmark")
            } description: {
                Text("The episode list didn't come back from the server.")
            } actions: {
                Button("Retry") { Task { await app.loadEpisodes(itemID: item.id) } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        }
    }

    private func list(_ episodes: [PodcastEpisode]) -> some View {
        let visible = filteredSorted(episodes)
        return VStack(spacing: 0) {
            headerRow(total: episodes.count)
            if visible.isEmpty {
                Text("No \(filter.rawValue.lowercased()) episodes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.xl)
            } else if let groups = seasonGroups(visible) {
                LazyVStack(spacing: 0) {
                    ForEach(groups, id: \.season) { group in
                        seasonHeader(group.season)
                        rows(group.episodes)
                    }
                }
            } else {
                LazyVStack(spacing: 0) { rows(visible) }
            }
        }
        .contentCard(cornerRadius: Theme.Radius.card)
    }

    @ViewBuilder private func rows(_ episodes: [PodcastEpisode]) -> some View {
        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
            if index > 0 {
                Divider().overlay(Theme.hairline).padding(.horizontal, Theme.Space.m)
            }
            EpisodeRow(item: item, episode: episode)
        }
    }

    private func headerRow(total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Episodes").font(.headline)
            Text("\(total)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            // Plain menu pickers: the current choice is the label.
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Show which episodes")
            Picker("Episode Order", selection: Binding(
                get: { app.episodeOrder(for: item) },
                set: { app.setEpisodeOrder($0, for: item) }
            )) {
                ForEach(EpisodeOrder.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Episode order, remembered for this show")
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.m)
        .padding(.bottom, Theme.Space.xs)
    }

    private func seasonHeader(_ season: String) -> some View {
        Text(season.isEmpty ? "Other Episodes" : "Season \(season)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.xs)
    }

    // MARK: Filtering / ordering

    private func filteredSorted(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
        // The show's remembered order (serial shows default to oldest-first);
        // sortDate keeps it consistent with nextEpisode's.
        app.episodeOrder(for: item).sorted(episodes.filter(matches))
    }

    private func matches(_ episode: PodcastEpisode) -> Bool {
        let progress = app.progress(itemID: item.id, episodeID: episode.id)
        switch filter {
        case .all: return true
        case .unplayed: return !(progress?.isFinished ?? false)
        case .downloaded: return app.downloads.isDownloaded(item.id, episodeID: episode.id)
        case .inProgress:
            return (progress?.fraction ?? 0) > 0.001 && !(progress?.isFinished ?? false)
        }
    }

    /// Buckets episodes by season, preserving list order; nil when no episode
    /// carries a season string (plain flat list).
    private func seasonGroups(_ episodes: [PodcastEpisode]) -> [(season: String, episodes: [PodcastEpisode])]? {
        guard episodes.contains(where: { !($0.season ?? "").isEmpty }) else { return nil }
        var order: [String] = []
        var buckets: [String: [PodcastEpisode]] = [:]
        for episode in episodes {
            let key = episode.season ?? ""
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(episode)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}
