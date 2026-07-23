import SwiftUI

/// Shelf card for a podcast episode (Home "Latest Episodes"): square cover with
/// hover play affordance, two-line episode title, show name, and a publish-date /
/// duration line. Clicking anywhere on the art streams the episode.
struct EpisodeCard: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    let episode: PodcastEpisode
    @State private var hovering = false

    /// Owning podcast item when it's already in the loaded library — display
    /// only. Recent-episodes results may reference items outside the library,
    /// so this can be nil (the card then renders from the podcast shell);
    /// actions resolve the item on demand via `app.resolveItem(id:)`.
    private var item: LibraryItem? {
        episode.libraryItemId.flatMap { app.item(byID: $0) }
    }

    private var progress: AppState.ItemProgress? {
        guard let itemID = episode.libraryItemId else { return nil }
        return app.progress(itemID: itemID, episodeID: episode.id)
    }

    private var showName: String {
        item?.title ?? episode.podcast?.metadata?.title ?? "Podcast"
    }

    private var coverURL: URL? {
        episode.libraryItemId.flatMap { app.coverURL(itemID: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Button(action: play) {
                    CoverArt(url: coverURL, title: showName)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(alignment: .bottom) { progressBar }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        }
                        .overlay(alignment: .topLeading) { downloadBadge }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(episode.displayTitle) from \(showName)")

                // Non-interactive affordance — the cover button underneath plays.
                if hovering {
                    RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous)
                        .fill(.black.opacity(0.38))
                        .allowsHitTesting(false)
                        .transition(.opacity)

                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                        .shadow(radius: 6)
                        .allowsHitTesting(false)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .hoverLift()
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)   // keeps shelf rows aligned
                    .multilineTextAlignment(.leading)
                Text(showName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(metaLine)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu { menu }
    }

    /// "2 days ago · 42 min" — whichever parts the feed provided.
    private var metaLine: String {
        var parts: [String] = []
        if let date = episode.publishedDate {
            parts.append(Format.relativeDate(date))
        }
        if let duration = durationString(episode.bestDuration) {
            parts.append(duration)
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    @ViewBuilder private var progressBar: some View {
        if let progress, progress.fraction > 0.001, !progress.isFinished {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.5))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * progress.fraction))
                }
            }
            .frame(height: 5)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private var downloadBadge: some View {
        if let itemID = episode.libraryItemId, app.downloads.isDownloaded(itemID, episodeID: episode.id) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .blue)
                .padding(8)
                .shadow(radius: 3)
        }
    }

    // Mirrors the book cards' context menu, scoped to a single episode. The
    // menu never hides behind item resolution — actions that need the full
    // item resolve it when invoked.
    @ViewBuilder private var menu: some View {
        Button("Play", systemImage: "play.fill", action: play)
        if let itemID = episode.libraryItemId {
            if progress?.isFinished == true {
                Button("Mark as Unplayed", systemImage: "circle") {
                    app.markEpisode(itemID: itemID, episodeID: episode.id, finished: false)
                }
            } else {
                Button("Mark as Played", systemImage: "checkmark.circle") {
                    app.markEpisode(itemID: itemID, episodeID: episode.id, finished: true)
                }
            }
            Divider()
            if app.downloads.isDownloaded(itemID, episodeID: episode.id) {
                Button("Remove Download", systemImage: "trash", role: .destructive) {
                    app.removeDownload(itemID: itemID, episodeID: episode.id)
                }
            } else if !app.downloads.isDownloading(itemID, episodeID: episode.id) {
                Button("Download for Offline", systemImage: "arrow.down.circle") { download(itemID) }
            }
        }
    }

    private func play() {
        guard let itemID = episode.libraryItemId else { return }
        Task {
            guard let resolved = await app.resolveItem(id: itemID) else {
                app.errorMessage = "Couldn't load the podcast for “\(episode.displayTitle)”."
                return
            }
            startPlayback(item: resolved, episode: episode, app: app, player: player)
        }
    }

    private func download(_ itemID: String) {
        Task {
            guard let resolved = await app.resolveItem(id: itemID) else {
                app.errorMessage = "Couldn't load the podcast for “\(episode.displayTitle)”."
                return
            }
            await app.startDownload(item: resolved, episode: episode)
        }
    }
}
