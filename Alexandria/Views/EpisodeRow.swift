import SwiftUI
import AppKit

/// One podcast episode row, in the shape of Apple Podcasts on the Mac: the
/// title, a two-line excerpt of the show notes (click to read them in full),
/// then one always-visible play button that carries the time — "▶ 39m",
/// "▶ 12m left" with a small progress bar, or "✓ Played" — beside the publish
/// date and a ⋯ menu. Nothing depends on hover, and a single click never
/// starts playback; double-click plays.
struct EpisodeRow: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: LibraryItem
    let episode: PodcastEpisode

    @State private var notesExpanded = false

    private var progress: AppState.ItemProgress? {
        app.progress(itemID: item.id, episodeID: episode.id)
    }
    private var isFinished: Bool { progress?.isFinished ?? false }
    private var inProgress: Bool { !isFinished && (progress?.fraction ?? 0) > 0.001 }
    private var isDownloaded: Bool { app.downloads.isDownloaded(item.id, episodeID: episode.id) }
    private var downloadFraction: Double? { app.downloads.downloadProgress(item.id, episodeID: episode.id) }
    private var isDownloading: Bool { app.downloads.isDownloading(item.id, episodeID: episode.id) }
    private var notesHTML: String { episode.description ?? episode.subtitle ?? "" }
    /// One flowing line of prose for the two-line preview: paragraph breaks
    /// collapsed, or "On today's tapes…" plus a blank line left an uneven gap.
    private var excerpt: String {
        plainText(fromHTML: notesHTML)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    /// This episode is the one loaded in the player (playing or paused).
    private var isCurrent: Bool { player.itemID == item.id && player.currentEpisodeID == episode.id }
    private var isPlayingNow: Bool { isCurrent && player.isPlaying }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(episode.displayTitle)
                .font(.body.weight(.semibold))
                // Played episodes recede through the title alone.
                .foregroundStyle(isFinished ? HierarchicalShapeStyle.secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !excerpt.isEmpty { notes }

            HStack(spacing: Theme.Space.s + 2) {
                playButton
                if let date = episode.publishedDate {
                    Text(Format.relativeDate(date))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help(date.formatted(date: .complete, time: .shortened))
                }
                Spacer(minLength: Theme.Space.s)
                downloadState
                moreMenu
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { isCurrent ? player.play() : play() }
        .contextMenu { menuItems }
        .queueDraggable(item, episode: episode)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Play") { play() }
        .accessibilityAction(named: isDownloaded ? "Remove Download" : "Download") { toggleDownload() }
        .accessibilityAction(named: isFinished ? "Mark as Unplayed" : "Mark as Played") { toggleFinished() }
    }

    // MARK: Notes

    /// Two lines of the notes as plain text; clicking opens the full notes
    /// (links live) in place.
    @ViewBuilder private var notes: some View {
        if notesExpanded {
            VStack(alignment: .leading, spacing: 6) {
                ShowNotesView(html: notesHTML)
                Button("Show Less") { toggleNotes() }
                    .buttonStyle(.link)
                    .font(.callout)
            }
            .transition(.opacity)
        } else {
            Button(action: toggleNotes) {
                Text(excerpt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show the full notes")
            .accessibilityLabel("Show notes")
            .accessibilityValue(excerpt)
        }
    }

    // MARK: Play

    /// The row's one prominent control: plays, and says how long it takes.
    /// On the episode in the player it fills with the accent and toggles
    /// play/pause, with a small live equalizer while audio is running.
    @ViewBuilder private var playButton: some View {
        if isCurrent {
            pill.buttonStyle(.borderedProminent).tint(.accentColor)
        } else {
            pill.buttonStyle(.bordered)
        }
    }

    private var pill: some View {
        Button {
            isCurrent ? player.toggle() : play()
        } label: {
            HStack(spacing: 5) {
                if isPlayingNow {
                    EqualizerBars()
                } else if isFinished && !isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption2.weight(.bold))
                }
                Text(playLabel)
                    .monospacedDigit()
                if inProgress, !isCurrent, let fraction = progress?.fraction {
                    ProgressView(value: min(max(fraction, 0), 1))
                        .progressViewStyle(.linear)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .help(isPlayingNow ? "Pause" : isFinished ? "Play Again" : inProgress ? "Resume" : "Play")
        .accessibilityLabel(playAccessibilityLabel)
    }

    private var playLabel: String {
        if isFinished { return "Played" }
        guard let duration = episode.bestDuration, duration > 0 else { return "Play" }
        if inProgress, let progress {
            return "\(Format.duration(max(0, duration * (1 - progress.fraction)))) left"
        }
        return Format.duration(duration)
    }

    private var playAccessibilityLabel: String {
        if isPlayingNow { return "Pause, now playing, \(playLabel)" }
        if isFinished { return "Play again, played" }
        return inProgress ? "Resume, \(playLabel)" : "Play, \(playLabel)"
    }

    // MARK: Trailing

    /// Shown only when there's something to say: downloading or downloaded.
    @ViewBuilder private var downloadState: some View {
        if let fraction = downloadFraction {
            ProgressView(value: fraction)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .help("Downloading… \(Int(fraction * 100))%")
        } else if isDownloaded {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.secondary)
                .help("Downloaded")
                .accessibilityLabel("Downloaded")
        }
    }

    private var moreMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("More")
        .accessibilityLabel("More actions for \(episode.displayTitle)")
    }

    @ViewBuilder private var menuItems: some View {
        Button(isFinished ? "Play Again" : inProgress ? "Resume" : "Play", systemImage: "play.fill") { play() }
        QueueMenuItems(item: item, episode: episode)
        Button(isFinished ? "Mark as Unplayed" : "Mark as Played",
               systemImage: isFinished ? "circle" : "checkmark.circle") {
            toggleFinished()
        }
        if !excerpt.isEmpty {
            Button(notesExpanded ? "Hide Notes" : "Show Notes", systemImage: "text.alignleft") { toggleNotes() }
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

    private func toggleNotes() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { notesExpanded.toggle() }
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
}

/// A tiny three-bar level meter for the episode that's playing — the
/// recognisable "this one is on" mark. It's an indicator, not audio analysis,
/// so it moves on a gentle fixed rhythm; under Reduce Motion it holds still.
private struct EqualizerBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { bar in
                    Capsule()
                        .frame(width: 2, height: height(bar: bar, time: t))
                }
            }
            .frame(width: 9, height: 10, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func height(bar: Int, time: Double) -> CGFloat {
        guard !reduceMotion else { return [6, 10, 4][bar] }
        // Three out-of-step waves, 3...10pt tall.
        let speeds = [5.1, 6.7, 4.3], offsets = [0.0, 1.9, 3.7]
        let wave = (sin(time * speeds[bar] + offsets[bar]) + 1) / 2
        return 3 + 7 * wave
    }
}
