import SwiftUI

struct ItemDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem

    @State private var detail: ItemDetail?
    @State private var descriptionExpanded = false
    @State private var chaptersExpanded = false
    /// True while the Play/Resume tap is building a session — the button
    /// disables so a slow server can't collect duplicate taps.
    @State private var launchingPlayback = false

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
        .overlay(alignment: .topTrailing) { closeButton }
        .task {
            if item.isPodcast {
                await app.loadEpisodes(itemID: item.id)
            } else {
                detail = await app.itemDetail(itemID: item.id)
            }
        }
    }

    private var bookContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
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
            VStack(alignment: .leading, spacing: 6) {
                Text(cleaned(description))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(descriptionExpanded ? nil : 4)
                    .textSelection(.enabled)
                Button(descriptionExpanded ? "Read less" : "Read more") {
                    withAnimation(.easeInOut(duration: 0.2)) { descriptionExpanded.toggle() }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
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
            Button(role: .destructive) {
                app.removeDownload(itemID: item.id)
            } label: {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.green)
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

    private var playLabel: String {
        if let progress, progress.fraction > 0.001, !progress.isFinished { return "Resume" }
        return "Play"
    }

    // MARK: Info grid

    private var infoGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow("Narrators", item.narrator)
            infoRow("Published", meta?.publishedYear)
            infoRow("Publisher", meta?.publisher)
            infoRow("Genres", meta?.genres?.joined(separator: ", "))
            infoRow("Tags", detail?.media?.tags?.joined(separator: ", "))
            infoRow("Language", meta?.language)
            infoRow("Duration", durationString(detail?.media?.duration ?? item.duration))
            infoRow("Size", sizeString(detail?.media?.size))
        }
    }

    @ViewBuilder private func infoRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text(label.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
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
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(progress.isFinished ? Color.green : Color.accentColor)
                            .frame(width: max(4, geo.size.width * progress.fraction))
                    }
                }
                .frame(height: 6)
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
            VStack(alignment: .leading, spacing: 6) {
                Text(cleaned(description))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(descriptionExpanded ? nil : 4)
                    .textSelection(.enabled)
                Button(descriptionExpanded ? "Read less" : "Read more") {
                    withAnimation(.easeInOut(duration: 0.2)) { descriptionExpanded.toggle() }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
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
                        LazyVStack(spacing: 0) {
                            ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                                HStack {
                                    Text("\(index + 1)").foregroundStyle(.secondary)
                                        .frame(width: 34, alignment: .leading)
                                    Text(chapter.title ?? "Chapter \(index + 1)").lineLimit(1)
                                    Spacer()
                                    Text(Format.timestamp(chapter.start ?? 0))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                .font(.callout)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.03) : .clear)
                            }
                        }
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

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.callout.weight(.bold))
                .foregroundStyle(.primary)
                .padding(8)
                .navGlassCircle()
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Close")
        .padding(14)
    }

    // MARK: Helpers

    private func cleaned(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
