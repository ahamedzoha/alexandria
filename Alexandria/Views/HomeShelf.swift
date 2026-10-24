import SwiftUI

/// A reusable edge-to-edge horizontal artwork shelf with the shared shelf-title
/// header, reusing the library grid's CoverCell at a fixed tile width.
struct HomeShelf: View {
    @Environment(AppState.self) private var app
    let title: String
    let symbol: String
    let items: [LibraryItem]
    var onSeeAll: (() -> Void)? = nil
    let onOpen: (LibraryItem) -> Void
    let onPlay: (LibraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: title, symbol: symbol, onSeeAll: onSeeAll)
                .padding(.horizontal, Theme.Space.xl)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Space.m) {
                    ForEach(items) { item in
                        BookShelfCard(item: item,
                                      onOpen: { onOpen(item) },
                                      onPlay: { onPlay(item) })
                            .frame(width: 150)
                            .scrollTransition { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
                                    .opacity(phase.isIdentity ? 1 : 0.85)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .clipsShelfEdges()
            .contentMargins(.horizontal, Theme.Space.xl, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
        }
    }
}

/// Book cover cell + the uniform library context menu, shared by HomeShelf and
/// ContinueShelf so a book card behaves identically on every shelf. The menu
/// mirrors LibraryGridView's per-item menu.
private struct BookShelfCard: View {
    @Environment(AppState.self) private var app
    let item: LibraryItem
    let onOpen: () -> Void
    let onPlay: () -> Void

    var body: some View {
        CoverCell(item: item, onOpen: onOpen, onPlay: onPlay)
            .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        Button("Play", systemImage: "play.fill", action: onPlay)
        if app.downloads.isDownloaded(item.id) {
            Button("Remove Download", systemImage: "trash", role: .destructive) {
                app.removeDownload(itemID: item.id)
            }
        } else if app.downloads.activeDownloads[item.id] == nil {
            Button("Download for Offline", systemImage: "arrow.down.circle") {
                Task { await app.startDownload(item: item) }
            }
        }
        Divider()
        Button("Show Author", systemImage: "person") {
            app.showGroup(kind: .authors, value: item.author)
        }
        Button("Show Details", systemImage: "info.circle", action: onOpen)
    }
}

/// The Continue Listening shelf: in-progress books AND podcast episodes mixed
/// in one row, most recently played first (the spillover after the hero).
/// Books render as cover cells, episodes as episode cards — each keeps the
/// exact affordances it has elsewhere, so resuming is one consistent gesture.
struct ContinueShelf: View {
    let title: String
    let symbol: String
    let entries: [AppState.ContinueEntry]
    var onSeeAll: (() -> Void)? = nil
    let onOpen: (LibraryItem) -> Void
    let onPlay: (LibraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: title, symbol: symbol, onSeeAll: onSeeAll)
                .padding(.horizontal, Theme.Space.xl)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Space.m) {
                    ForEach(entries) { entry in
                        card(for: entry)
                            .frame(width: 150)
                            .scrollTransition { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
                                    .opacity(phase.isIdentity ? 1 : 0.85)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .clipsShelfEdges()
            .contentMargins(.horizontal, Theme.Space.xl, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
        }
    }

    @ViewBuilder private func card(for entry: AppState.ContinueEntry) -> some View {
        switch entry {
        case .book(let item, let progress):
            // Episode cards carry a text footer; a bare cover next to them
            // reads ragged, so book entries get the matching anatomy here
            // (title / author / time left) — only on this mixed shelf.
            VStack(alignment: .leading, spacing: 8) {
                BookShelfCard(item: item,
                              onOpen: { onOpen(item) },
                              onPlay: { onPlay(item) })
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Text(item.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(remainingLabel(item: item, progress: progress))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .episode(let episode, let show, _):
            // The resolved show fills in the name when the podcast lives
            // outside the loaded library (episode lists don't carry a shell).
            EpisodeCard(episode: episode, show: show)
        }
    }

    /// "12 hr 4 min left" — mirrors the hero's remaining readout.
    private func remainingLabel(item: LibraryItem, progress: AppState.ItemProgress) -> String {
        let remaining = (item.duration ?? 0) * (1 - progress.fraction)
        return durationString(remaining).map { "\($0) left" } ?? " "
    }
}

/// Horizontal shelf of podcast episode cards (Home "Latest Episodes"), matching
/// HomeShelf's header + edge-to-edge scroll treatment. No See-All: there is no
/// episode-filtered library view to send it to.
struct EpisodeShelf: View {
    let title: String
    let symbol: String
    let episodes: [PodcastEpisode]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: title, symbol: symbol)
                .padding(.horizontal, Theme.Space.xl)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Space.m) {
                    ForEach(episodes) { episode in
                        EpisodeCard(episode: episode)
                            .frame(width: 150)
                            .scrollTransition { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
                                    .opacity(phase.isIdentity ? 1 : 0.85)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .clipsShelfEdges()
            .contentMargins(.horizontal, Theme.Space.xl, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
        }
    }
}

/// Section header: shared shelf-title label + a quiet "See All" chevron
/// affordance where a destination exists.
struct SectionHeader: View {
    let title: String
    let symbol: String
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol)
                .font(Theme.Typography.shelfTitle)
                .labelStyle(.titleAndIcon)
            Spacer()
            if let onSeeAll {
                Button(action: onSeeAll) {
                    HStack(spacing: 3) {
                        Text("See All")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show all in Library")
            }
        }
    }
}

private extension View {
    /// Shelves draw past their bounds so hover lift and shadows aren't cut off,
    /// but they must stop at the column's sides — otherwise covers slide in
    /// under the Now Playing inspector. Clips horizontally only.
    func clipsShelfEdges() -> some View {
        mask { Rectangle().padding(.vertical, -Theme.Space.xl) }
    }
}
