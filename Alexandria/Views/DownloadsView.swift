import SwiftUI

/// Everything downloaded to this Mac — books, then each show's episodes —
/// with what it costs on disk. Works with no connection: rows come from the
/// download records themselves, items from the offline snapshot.
struct DownloadsView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @State private var confirmRemoveFinished = false
    @State private var selected: LibraryItem?

    private var books: [DownloadedBook] {
        app.downloads.downloadedBooks.filter { $0.episodeID == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Episodes grouped by show, shows A–Z, episodes newest download first.
    private var shows: [(title: String, episodes: [DownloadedBook])] {
        Dictionary(grouping: app.downloads.downloadedBooks.filter { $0.episodeID != nil }, by: \.itemID)
            .map { (title: $0.value.first?.title ?? "", episodes: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Group {
            if app.downloads.downloadedBooks.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download a book or an episode from its ⋯ menu to listen without a connection.")
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await app.downloads.refreshSizes() }
        .itemDetailSheet($selected)
        .confirmationDialog("Remove \(Format.count(app.finishedDownloads.count, "finished download"))?",
                            isPresented: $confirmRemoveFinished) {
            Button("Remove", role: .destructive) { app.removeDownloads(app.finishedDownloads) }
        } message: {
            Text(app.finishedDownloads.map { $0.episodeTitle ?? $0.title }.joined(separator: ", "))
        }
    }

    private var list: some View {
        List {
            Section {
                summary
            }
            if !books.isEmpty {
                Section("Books") {
                    ForEach(books) { DownloadRow(download: $0, onOpen: open) }
                }
            }
            ForEach(shows, id: \.title) { show in
                Section(show.title) {
                    ForEach(show.episodes) { DownloadRow(download: $0, onOpen: open) }
                }
            }
        }
        .listStyle(.inset)
    }

    private var summary: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.count(app.downloads.downloadedBooks.count, "download"))
                    .font(.headline)
                Text("\(sizeString(Double(app.downloads.totalSize)) ?? "Measuring…") on this Mac")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button("Remove Finished…") { confirmRemoveFinished = true }
                .disabled(app.finishedDownloads.isEmpty)
                .help("Remove downloads you've listened to the end")
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private func open(_ download: DownloadedBook) {
        selected = app.knownItem(for: download)
    }
}

/// One download: cover, title, where it's from, how far in, and its size.
private struct DownloadRow: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    let download: DownloadedBook
    let onOpen: (DownloadedBook) -> Void

    private var progress: AppState.ItemProgress? {
        app.progress(itemID: download.itemID, episodeID: download.episodeID)
    }
    private var isCurrent: Bool {
        player.itemID == download.itemID && player.currentEpisodeID == download.episodeID
    }
    /// An episode needs its episode record to start; a book never does.
    private var canPlay: Bool { download.episodeID == nil || app.knownEpisode(for: download) != nil }

    var body: some View {
        HStack(spacing: Theme.Space.s + 2) {
            RemoteImage(url: app.downloads.localCoverURL(download.itemID)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } fallback: {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(.quaternary)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(download.episodeTitle ?? download.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            if let size = app.downloads.sizes[download.id] {
                Text(sizeString(Double(size)) ?? "")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button {
                isCurrent ? player.toggle() : play()
            } label: {
                Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                    .iconHitTarget()
            }
            .buttonStyle(.borderless)
            .disabled(!canPlay)
            .help(isCurrent && player.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(isCurrent && player.isPlaying ? "Pause" : "Play")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if canPlay { play() } }
        .contextMenu {
            Button("Play", systemImage: "play.fill") { play() }.disabled(!canPlay)
            Button("Show Details", systemImage: "info.circle") { onOpen(download) }
            Divider()
            Button("Remove Download", systemImage: "trash", role: .destructive) {
                app.removeDownload(itemID: download.itemID, episodeID: download.episodeID)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Stephen King · 37% · 7 hr left" / "Radio Rental · Played".
    private var detailLine: String {
        var parts = [download.episodeID == nil ? download.author : download.title]
        if let progress, progress.isFinished {
            parts.append(download.episodeID == nil ? "Finished" : "Played")
        } else if let progress, progress.fraction > 0.001 {
            parts.append("\(Int(progress.fraction * 100))%")
            if let left = durationString(download.duration * (1 - progress.fraction)) { parts.append("\(left) left") }
        } else if let total = durationString(download.duration) {
            parts.append(total)
        }
        return parts.joined(separator: " · ")
    }

    private func play() {
        guard let item = app.knownItem(for: download) else { return }
        startPlayback(item: item, episode: app.knownEpisode(for: download), app: app, player: player)
    }
}
