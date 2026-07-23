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
                    .padding(.vertical, 28)
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
        HStack {
            Text("Episodes").font(.headline)
            Text("\(total)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Theme.Space.s).padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
            Spacer()
            Menu {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label(filter == .all ? "Filter" : filter.rawValue,
                      systemImage: "line.3.horizontal.decrease.circle")
            }
            .fixedSize()
            .help("Filter episodes")
        }
        .padding(Theme.Space.m)
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
        // Serial shows should read oldest-first, but the podcast type isn't in
        // our metadata models yet — newest-first for everything until it is.
        // sortDate keeps this ordering consistent with nextEpisode's.
        episodes.filter(matches)
            .sorted { $0.sortDate > $1.sortDate }
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
