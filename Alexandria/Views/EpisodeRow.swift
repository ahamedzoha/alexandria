import SwiftUI
import AppKit

/// One podcast episode row: publish date, title, remaining time, progress /
/// download state, hover-to-play (the whole row also plays on click), and an
/// expandable show-notes disclosure.
struct EpisodeRow: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    let item: LibraryItem
    let episode: PodcastEpisode

    @State private var hovering = false
    @State private var notesExpanded = false

    private var progress: AppState.ItemProgress? {
        app.progress(itemID: item.id, episodeID: episode.id)
    }
    private var isFinished: Bool { progress?.isFinished ?? false }
    private var inProgress: Bool { !isFinished && (progress?.fraction ?? 0) > 0.001 }
    private var isDownloaded: Bool { app.downloads.isDownloaded(item.id, episodeID: episode.id) }
    private var downloadFraction: Double? { app.downloads.downloadProgress(item.id, episodeID: episode.id) }
    private var isDownloading: Bool { app.downloads.isDownloading(item.id, episodeID: episode.id) }
    private var hasNotes: Bool { !(episode.description ?? episode.subtitle ?? "").isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                rowButton
                trailingControls
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 10)

            if notesExpanded {
                ShowNotesView(html: episode.description ?? episode.subtitle ?? "")
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.bottom, Theme.Space.m)
            }
        }
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
    }

    // MARK: Main content (click / keyboard plays)

    private var rowButton: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 4) {
                if let date = episode.publishedDate {
                    Text(Format.relativeDate(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(date.formatted(date: .abbreviated, time: .shortened))
                }
                Text(episode.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                metaRow
                if inProgress { progressBar }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isFinished ? 0.55 : 1)   // played episodes recede
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Plays the episode")
        .accessibilityAction(named: isDownloaded ? "Remove Download" : "Download") { toggleDownload() }
        .accessibilityAction(named: isFinished ? "Mark as Unplayed" : "Mark as Played") { toggleFinished() }
    }

    @ViewBuilder private var metaRow: some View {
        HStack(spacing: Theme.Space.s) {
            if isFinished {
                Label("Played", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if let remaining = remainingText {
                Text(remaining)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .help("Downloaded")
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(3, geo.size.width * (progress?.fraction ?? 0)))
            }
        }
        .frame(height: 3)
        .padding(.top, 2)
    }

    // MARK: Trailing controls

    private var trailingControls: some View {
        HStack(spacing: Theme.Space.s) {
            downloadControl

            Button(action: play) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .help("Play")
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .accessibilityHidden(true)   // the row itself plays

            if hasNotes {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { notesExpanded.toggle() }
                } label: {
                    Image(systemName: notesExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(notesExpanded ? "Hide show notes" : "Show notes")
                .accessibilityLabel(notesExpanded ? "Hide show notes" : "Show notes")
            }
        }
    }

    @ViewBuilder private var downloadControl: some View {
        if let fraction = downloadFraction {
            ProgressView(value: fraction)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .help("Downloading… \(Int(fraction * 100))%")
        } else if !isDownloaded {
            Button(action: download) {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Download episode")
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .accessibilityHidden(true)   // covered by the row's Download action
        }
    }

    // MARK: Context menu

    @ViewBuilder private var menuItems: some View {
        Button("Play", systemImage: "play.fill") { play() }
        Button(isFinished ? "Mark as Unplayed" : "Mark as Played",
               systemImage: isFinished ? "circle" : "checkmark.circle") {
            toggleFinished()
        }
        Divider()
        if isDownloaded {
            Button("Remove Download", systemImage: "trash", role: .destructive) {
                app.removeDownload(itemID: item.id, episodeID: episode.id)
            }
        } else if !isDownloading {
            Button("Download", systemImage: "arrow.down.circle") { download() }
        }
        Button("Copy Episode Link", systemImage: "link") { copyLink() }
    }

    // MARK: Actions

    private func play() {
        startPlayback(item: item, episode: episode, app: app, player: player)
    }

    private func toggleFinished() {
        app.markEpisode(itemID: item.id, episodeID: episode.id, finished: !isFinished)
    }

    private func download() {
        Task { await app.startDownload(item: item, episode: episode) }
    }

    private func toggleDownload() {
        if isDownloaded {
            app.removeDownload(itemID: item.id, episodeID: episode.id)
        } else if !isDownloading {
            download()
        }
    }

    private func copyLink() {
        let base = app.serverURL.hasSuffix("/") ? String(app.serverURL.dropLast()) : app.serverURL
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(base)/item/\(item.id)", forType: .string)
    }

    // MARK: Formatting

    private var remainingText: String? {
        guard let duration = episode.bestDuration, duration > 0 else { return nil }
        if inProgress, let progress {
            return "\(Format.duration(max(0, duration * (1 - progress.fraction)))) left"
        }
        return Format.duration(duration)
    }

    private var accessibilitySummary: String {
        var parts = [episode.displayTitle]
        if let date = episode.publishedDate {
            parts.append(Format.relativeDate(date))
        }
        if let remaining = remainingText { parts.append(remaining) }
        if isFinished { parts.append("Played") }
        if isDownloaded { parts.append("Downloaded") }
        return parts.joined(separator: ", ")
    }
}
