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
                        CoverCell(item: item,
                                  onOpen: { onOpen(item) },
                                  onPlay: { onPlay(item) })
                            .frame(width: 150)
                            .contextMenu { menu(for: item) }
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
            .contentMargins(.horizontal, Theme.Space.xl, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
        }
    }

    // Mirrors LibraryGridView's per-item context menu so behavior is uniform.
    @ViewBuilder private func menu(for item: LibraryItem) -> some View {
        Button("Play", systemImage: "play.fill") { onPlay(item) }
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
        Button("Show Details", systemImage: "info.circle") { onOpen(item) }
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
