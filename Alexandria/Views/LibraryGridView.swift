import SwiftUI

struct LibraryGridView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: LibraryItem?

    // Cover wall: tight gutters so the artwork reads as one continuous surface.
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: Theme.Space.s)]

    private var isPodcastLibrary: Bool {
        app.libraries.first { $0.id == app.selectedLibraryID }?.mediaType == "podcast"
    }

    var body: some View {
        Group {
            if app.isLoading && app.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if app.items.isEmpty, let error = app.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't Load Library", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await app.loadLibraries() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if app.visibleItems.isEmpty {
                if app.items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing on this shelf yet", systemImage: "books.vertical")
                    } description: {
                        Text("When your server finishes scanning, your \(isPodcastLibrary ? "shows" : "books") land here — ready to play.")
                    } actions: {
                        Button("Refresh Library") { Task { await app.loadLibraries() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search or filter.")
                    )
                }
            } else if app.viewMode == .grid {
                gridView
            } else {
                tableView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selected) { item in
            ItemDetailView(item: item)
                .frame(width: item.isPodcast ? 640 : 560, height: item.isPodcast ? 760 : 680)
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(app.visibleItems) { item in
                    CoverCell(item: item,
                              onOpen: { selected = item },
                              onPlay: { playItem(item) })
                        .contextMenu { contextMenu(item) }
                }
            }
            .padding(Theme.Space.l)
            // Sort/filter/search reflows glide instead of snapping.
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: app.visibleItems)
        }
    }

    private var tableView: some View {
        Table(app.visibleItems) {
            TableColumn("Title") { item in
                HStack(spacing: 8) {
                    RemoteImage(url: app.coverURL(itemID: item.id)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } fallback: {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(item.title).lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { selected = item }
                .contextMenu { contextMenu(item) }
            }
            TableColumn("Author") { item in Text(item.author).lineLimit(1) }
            if isPodcastLibrary {
                // Podcasts have no narrator/duration; the episode count is the
                // useful shape-of-the-show number.
                TableColumn("Episodes") { item in
                    Text(item.numEpisodes.map(String.init) ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                TableColumn("Narrator") { item in
                    Text(item.narrator ?? "—")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                TableColumn("Duration") { item in
                    Text(durationString(item.duration) ?? "—").monospacedDigit().foregroundStyle(.secondary)
                }
                TableColumn("Progress") { item in progressCell(item) }
            }
        }
    }

    @ViewBuilder private func progressCell(_ item: LibraryItem) -> some View {
        let p = app.progress(itemID: item.id)
        if p?.isFinished == true {
            Label("Finished", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        } else if let p, p.fraction > 0.001 {
            Text("\(Int(p.fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private func contextMenu(_ item: LibraryItem) -> some View {
        Button("Play", systemImage: "play.fill") { playItem(item) }
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
        Button("Show Author", systemImage: "person") { app.showGroup(kind: .authors, value: item.author) }
        Button("Show Details", systemImage: "info.circle") { selected = item }
    }

    private func playItem(_ item: LibraryItem) {
        startPlayback(item: item, app: app, player: player)
    }
}

/// One tile of the cover wall. The artwork is the interface: metadata lives in
/// a hover/focus scrim inside the cover, progress is a persistent accent line
/// along the bottom edge, and state badges sit in the corners. Click opens
/// details; Return (or the "Play" accessibility action) plays.
struct CoverCell: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: LibraryItem
    let onOpen: () -> Void
    let onPlay: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    /// Artwork-derived color; nil until extraction lands (render never blocks).
    @State private var palette: ArtworkPalette?

    private var coverURL: URL? { app.coverURL(itemID: item.id) }
    private var progress: AppState.ItemProgress? { app.progress(itemID: item.id) }
    private var isFinished: Bool { progress?.isFinished == true }
    private var inProgress: Bool { !isFinished && (progress?.fraction ?? 0) > 0.001 }
    /// Metadata reveals on pointer hover and on keyboard focus alike.
    private var revealed: Bool { hovering || focused }

    var body: some View {
        ZStack {
            Button(action: onOpen) { cover }
                .buttonStyle(.plain)

            if revealed {
                playButton
            }
        }
        // .activate scopes focus to keyboard navigation (Tab / Full Keyboard
        // Access): plain .focusable() also takes focus on mouse click, leaving
        // the accent ring stuck on the cell after clicking or closing a sheet.
        .focusable(true, interactions: .activate)
        .focused($focused)
        .focusEffectDisabled(false)   // standard accent focus ring, no custom glow
        .contentShape(.focusEffect, RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous))
        .onKeyPress(.return) {
            onPlay()
            return .handled
        }
        .hoverLift()
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: revealed)
        // The palette only feeds the in-progress accent line, so skip
        // extraction for the (vast) majority of tiles that don't need it.
        // The id flips to the URL when progress appears, triggering the fetch.
        .task(id: inProgress ? coverURL : nil) {
            guard inProgress else { return }
            palette = await PaletteStore.shared.palette(for: coverURL)
        }
        .help("\(item.title) — \(item.author)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Shows details")
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: "Play") { onPlay() }
    }

    private var cover: some View {
        CoverArt(url: coverURL, title: item.title)
            .aspectRatio(1, contentMode: .fit)
            .overlay { finishedScrim }
            .overlay(alignment: .bottom) { hoverScrim }
            .overlay(alignment: .bottom) { progressEdge }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) { finishedBadge }
            .overlay(alignment: .topLeading) { downloadBadge }
    }

    // MARK: Hover / focus scrim (title + episode count, inside the cover)

    @ViewBuilder private var hoverScrim: some View {
        if revealed {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Typography.cardTitle)
                    .lineLimit(1)
                if item.isPodcast, let count = item.numEpisodes {
                    Text("\(count) episode\(count == 1 ? "" : "s")")
                        .font(Theme.Typography.meta)
                        .opacity(0.85)
                } else if !item.isPodcast {
                    Text(item.author)
                        .font(Theme.Typography.meta)
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            // Fixed white over an on-artwork scrim: semantic colors would
            // invert in light mode and vanish against the darkened artwork.
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .padding(.top, Theme.Space.xl)
            .background {
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    // MARK: Persistent progress (bottom-edge accent line)

    @ViewBuilder private var progressEdge: some View {
        if inProgress, let progress {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.25))
                    Rectangle()
                        // Artwork-derived pop color; app accent until it lands.
                        .fill((palette ?? .neutral).accent)
                        .frame(width: max(3, geo.size.width * progress.fraction))
                }
            }
            .frame(height: 3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Quick play (hover / focus only)

    private var playButton: some View {
        Button(action: onPlay) {
            Image(systemName: "play.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .help("Play")
        .accessibilityHidden(true)   // mirrored by the cell's "Play" action
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
    }

    // MARK: Persistent state badges

    @ViewBuilder private var finishedScrim: some View {
        if isFinished {
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder private var finishedBadge: some View {
        if isFinished {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Circle().fill(.green))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                .padding(6)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
    }

    @ViewBuilder private var downloadBadge: some View {
        if app.downloads.isDownloaded(item.id) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .blue)
                .padding(6)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
    }

    // MARK: Accessibility

    private var accessibilitySummary: String {
        var parts = ["\(item.title) by \(item.author)"]
        if item.isPodcast, let count = item.numEpisodes {
            parts.append("\(count) episode\(count == 1 ? "" : "s")")
        }
        if isFinished {
            parts.append("Finished")
        } else if let progress, inProgress {
            parts.append("\(Int(progress.fraction * 100))% played")
        }
        if app.downloads.isDownloaded(item.id) { parts.append("Downloaded") }
        return parts.joined(separator: ", ")
    }
}

/// Cover image with a blurred backfill (so mixed aspect ratios sit in a uniform
/// square tile without cropping) and a colorful title fallback when there is no art.
struct CoverArt: View {
    let url: URL?
    let title: String

    var body: some View {
        RemoteImage(url: url) { image in
            ZStack {
                image.resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: 22).opacity(0.55)
                image.resizable().aspectRatio(contentMode: .fit)
            }
        } fallback: {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Image(systemName: "headphones")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.85))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 10)
            }
            .padding(8)
        }
    }

    private var gradientColors: [Color] { Theme.placeholderColors(seed: title) }
}
