import SwiftUI

struct ItemDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem

    @State private var detail: ItemDetail?
    @State private var detailLoaded = false
    @State private var chaptersExpanded = false
    /// True while the Play/Resume tap is building a session — the button
    /// disables so a slow server can't collect duplicate taps.
    @State private var launchingPlayback = false
    @State private var confirmingRemoval = false

    private var coverURL: URL? {
        app.downloads.localCoverURL(item.id) ?? app.coverURL(itemID: item.id)
    }
    private var progress: AppState.ItemProgress? { app.progress(itemID: item.id) }
    private var meta: ItemDetail.Media.Meta? { detail?.media?.metadata }

    var body: some View {
        ScrollView {
            if item.isPodcast {
                podcastContent
            } else {
                bookContent
            }
        }
        .background(background)
        // A Mac sheet ends in a bar with its dismiss button (as Add Server
        // does), not a floating iOS-style ✕. Esc still closes it.
        .safeAreaInset(edge: .bottom, spacing: 0) { doneBar }
        .onExitCommand { dismiss() }
        .task {
            if item.isPodcast {
                await app.loadEpisodes(itemID: item.id)
            } else {
                detail = await app.itemDetail(itemID: item.id)
                detailLoaded = true
            }
        }
    }

    private var bookContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if app.webRatingsEnabled {
                RatingsSection(query: ratingsQuery)
            }
            infoGrid
            progressCard
            descriptionSection
            sectionRows
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Podcast layout (episode list instead of chapters/tracks)

    private var podcastContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            podcastHeader
            podcastDescription
            EpisodeListView(item: item)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var podcastHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            coverArt
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.title.bold())
                // Many feeds set author == show title; repeating it is noise.
                if !item.author.isEmpty, item.author != item.title {
                    Text(item.author).font(.title3).foregroundStyle(.secondary)
                }
                if let count = app.episodes(for: item.id)?.count ?? item.numEpisodes {
                    Label("\(count) episode\(count == 1 ? "" : "s")",
                          systemImage: "antenna.radiowaves.left.and.right")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var podcastDescription: some View {
        if let description = item.media?.metadata?.description, !description.isEmpty {
            ExpandableText(text: plainText(fromHTML: description))
        }
    }

    // MARK: Background (subtle cover bleed, fading into the window background)

    private var background: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
            RemoteImage(url: coverURL) { image in
                image.resizable().scaledToFill()
            } fallback: {
                Color.clear
            }
            .frame(maxWidth: .infinity)
            .frame(height: 340)
            .clipped()
            .blur(radius: 70)
            .saturation(1.4)
            .opacity(0.5)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private var coverArt: some View {
        RemoteImage(url: coverURL) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } fallback: {
            RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial)
                .overlay(Image(systemName: "headphones").font(.largeTitle).foregroundStyle(.secondary))
        }
        .frame(width: 150, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
        .themeShadow(Theme.Shadow.lifted)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                coverArt

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.title.bold())
                    if let subtitle = meta?.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.title3).foregroundStyle(.secondary)
                    }
                    Text("by \(item.author)").font(.title3).foregroundStyle(.secondary)
                    if let series = item.seriesBaseName {
                        Label(series, systemImage: "books.vertical")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }

            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                launchingPlayback = true
                startPlayback(item: item, app: app, player: player) { success in
                    launchingPlayback = false
                    if success { dismiss() }
                }
            } label: {
                Label(playLabel, systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(launchingPlayback)

            downloadButton
        }
    }

    @ViewBuilder private var downloadButton: some View {
        if app.downloads.isDownloaded(item.id) {
            // Reads as a status, so a click asks before deleting anything.
            Button {
                confirmingRemoval = true
            } label: {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.green)
            .help("Remove Download…")
            .confirmationDialog("Remove the download of “\(item.title)”?",
                                isPresented: $confirmingRemoval) {
                Button("Remove Download", role: .destructive) {
                    app.removeDownload(itemID: item.id)
                }
            } message: {
                Text("It stays in your library and can still be streamed or downloaded again.")
            }
        } else if let fraction = app.downloads.activeDownloads[item.id] {
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                Text("\(Int(fraction * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else {
            Button {
                Task { await app.startDownload(item: item) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    /// Waits for the detail fetch; falls back to the list item's fields if it failed.
    private var ratingsQuery: RatingsQuery? {
        guard detailLoaded else { return nil }
        return RatingsQuery(meta: meta, fallbackTitle: item.title,
                            fallbackAuthor: item.author, fallbackNarrator: item.narrator)
    }

    private var playLabel: String {
        if let progress, progress.fraction > 0.001, !progress.isFinished { return "Resume" }
        return "Play"
    }

    // MARK: Info grid

    private var infoGrid: some View {
        MetadataRows(rows: [
            ("Narrators", item.narrator),
            ("Published", meta?.publishedYear),
            ("Publisher", meta?.publisher),
            ("Genres", meta?.genres?.joined(separator: ", ")),
            ("Tags", detail?.media?.tags?.joined(separator: ", ")),
            ("Language", meta?.language),
            ("Duration", durationString(detail?.media?.duration ?? item.duration)),
            ("Size", sizeString(detail?.media?.size)),
        ])
    }

    // MARK: Progress

    @ViewBuilder private var progressCard: some View {
        if let progress, progress.fraction > 0.001 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(progress.isFinished ? "Finished" : "Your progress")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(progress.fraction * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(1, max(0, progress.fraction)))
                    .progressViewStyle(.linear)
                    .tint(progress.isFinished ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
                if !progress.isFinished, let duration = detail?.media?.duration ?? item.duration {
                    Text("\(durationString(duration * (1 - progress.fraction)) ?? "") remaining")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Description

    @ViewBuilder private var descriptionSection: some View {
        if let description = meta?.description, !description.isEmpty {
            ExpandableText(text: plainText(fromHTML: description))
        }
    }

    // MARK: Section rows (chapters / tracks / files)

    private var sectionRows: some View {
        VStack(spacing: 10) {
            if let chapters = detail?.media?.chapters, !chapters.isEmpty {
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { chaptersExpanded.toggle() }
                    } label: {
                        sectionHeader("Chapters", count: chapters.count,
                                      chevron: chaptersExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain)

                    if chaptersExpanded {
                        // Click to jump; a book that isn't loaded starts there.
                        let isLoaded = player.itemID == item.id
                        let current = isLoaded ? player.currentChapterIndex : nil
                        LazyVStack(spacing: 2) {
                            ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                                let start = chapter.start ?? 0
                                ChapterRow(number: index + 1,
                                           title: chapter.title ?? "Chapter \(index + 1)",
                                           start: start,
                                           isCurrent: index == current,
                                           isPlayed: current.map { index < $0 } ?? false,
                                           onSelect: {
                                               if isLoaded {
                                                   player.seek(to: start)
                                               } else {
                                                   startPlayback(item: item, startAt: start, app: app, player: player)
                                               }
                                           })
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let tracks = detail?.media?.audioFiles {
                staticRow("Audio Tracks", count: tracks.count)
            }
            if let files = detail?.libraryFiles {
                staticRow("Library Files", count: files.count)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int, chevron: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
            Image(systemName: chevron).foregroundStyle(.secondary)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func staticRow(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.headline)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var doneBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

}

extension View {
    /// Presents a book's or show's details: the one sheet every surface uses,
    /// sized for its content — a show's episode list gets more room.
    func itemDetailSheet(_ item: Binding<LibraryItem?>) -> some View {
        sheet(item: item) { item in
            let size = item.isPodcast ? CGSize(width: 640, height: 760) : CGSize(width: 560, height: 680)
            ItemDetailView(item: item)
                .frame(width: size.width, height: size.height)
        }
    }
}
