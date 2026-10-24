import SwiftUI

/// Trailing inspector for whatever is loaded in the player — it follows the
/// player, not the library selection. Cover and credits, chapters (click to
/// jump), the description and metadata, the author, and links out. Mounted by
/// MainView via `.inspector`; toggled from the Now Playing bar, the toolbar,
/// and Playback ▸ Show Info.
struct NowPlayingInspector: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        Group {
            if player.itemID.isEmpty {
                ContentUnavailableView("Nothing Playing", systemImage: "headphones",
                                       description: Text("Start a book or an episode and its details show up here."))
            } else {
                // Fresh state per item, so nothing from the last book lingers.
                NowPlayingDetails(itemID: player.itemID, episodeID: player.currentEpisodeID)
                    .id("\(player.itemID)|\(player.currentEpisodeID ?? "")")
            }
        }
        .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
    }
}

private struct NowPlayingDetails: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @Environment(\.colorScheme) private var colorScheme
    let itemID: String
    let episodeID: String?

    private enum LoadState { case loading, loaded, failed }

    @State private var detail: ItemDetail?
    @State private var episode: PodcastEpisode?
    @State private var authors: [AuthorDetail] = []
    @State private var loadState = LoadState.loading
    @State private var palette: ArtworkPalette?

    private var meta: ItemDetail.Media.Meta? { detail?.media?.metadata }
    private var item: LibraryItem? { app.item(byID: itemID) }
    private var isEpisode: Bool { episodeID != nil }
    /// The artwork's accent where it reads against the panel, else the
    /// system accent (a dark brown cover accent vanishes on dark chrome).
    private var accent: Color {
        guard let candidate = palette?.accent else { return .accentColor }
        let panel = colorScheme == .dark ? Color(white: 0.16) : .white
        return ArtworkPalette.contrastRatio(candidate, panel) >= 3 ? candidate : .accentColor
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header
                    NowPlayingProgressLine()

                    if app.webRatingsEnabled && !isEpisode {
                        Divider()
                        RatingsSection(query: ratingsQuery, accent: accent)
                    }

                    if !player.chapters.isEmpty {
                        Divider()
                        ChapterSection(accent: accent) { id in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }

                    if isEpisode {
                        episodeSections
                    } else {
                        bookSections
                    }
                }
                .padding(Theme.Space.l)
            }
        }
        .task { await load() }
        .task(id: player.coverURL) {
            palette = await PaletteStore.shared.palette(for: player.coverURL)
        }
    }

    /// Waits for the detail fetch; if that failed (offline), matches on what
    /// the player knows.
    private var ratingsQuery: RatingsQuery? {
        guard loadState != .loading else { return nil }
        return RatingsQuery(meta: meta, fallbackTitle: player.currentTitle,
                            fallbackAuthor: player.currentAuthor, fallbackNarrator: item?.narrator)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CoverArt(url: player.coverURL, title: player.currentTitle)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 280)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous)
                    .strokeBorder(Theme.hairline))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                    .textSelection(.enabled)
                Text(byline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let narrators {
                    Text("Narrated by \(narrators)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let series = seriesLink {
                    Button(series.label) { app.showGroup(kind: .series, value: series.group) }
                        .buttonStyle(.link)
                        .font(.callout)
                        .padding(.top, 2)
                        .help("Show this series in the library")
                }
            }
        }
    }

    private var byline: String {
        if isEpisode { return player.currentAuthor }   // the show's name
        let names = (meta?.authors ?? []).compactMap(\.name)
        return names.isEmpty ? player.currentAuthor : names.joined(separator: ", ")
    }

    private var narrators: String? {
        if let list = meta?.narrators, !list.isEmpty { return list.joined(separator: ", ") }
        return meta?.narratorName ?? item?.narrator
    }

    /// "Book 7 of The Dark Tower" — grouped by the same base name the library
    /// grid filters on.
    private var seriesLink: (label: String, group: String)? {
        let entry = meta?.series?.first
        guard let group = item?.seriesBaseName ?? entry?.name, !group.isEmpty else { return nil }
        if let sequence = entry?.sequence, !sequence.isEmpty {
            return ("Book \(sequence) of \(group)", group)
        }
        return (group, group)
    }

    // MARK: Books

    @ViewBuilder private var bookSections: some View {
        Divider()
        section("About") {
            switch loadState {
            case .loading:
                ProgressView().controlSize(.small)
            case .failed:
                unavailable
            case .loaded:
                if let description = meta?.description, !description.isEmpty {
                    ExpandableText(text: plainText(fromHTML: description))
                }
                MetadataRows(rows: [
                    ("Published", meta?.publishedYear),
                    ("Publisher", meta?.publisher),
                    ("Genres", meta?.genres?.joined(separator: ", ")),
                    ("Language", meta?.language),
                    ("Length", durationString(player.duration)),
                ], labelWidth: 84)
            }
        }

        let bios = authors.filter { !($0.description ?? "").isEmpty }
        if !bios.isEmpty {
            Divider()
            section(bios.count == 1 ? "About the Author" : "About the Authors") {
                ForEach(bios) { author in
                    AuthorBlurb(author: author)
                }
            }
        }

        Divider()
        section("Elsewhere") {
            elsewhereLinks
        }
    }

    @ViewBuilder private var elsewhereLinks: some View {
        let title = meta?.title ?? player.currentTitle
        let author = byline
        VStack(alignment: .leading, spacing: 8) {
            if let url = ExternalLinks.audible(asin: meta?.asin, title: title, author: author,
                                              domain: app.audibleStore.domain) {
                externalLink("Audible", url)
            }
            if let url = ExternalLinks.goodreads(isbn: meta?.isbn, title: title, author: author) {
                externalLink("Goodreads", url)
            }
            if let url = ExternalLinks.storyGraph(title: title, author: author) {
                externalLink("The StoryGraph", url)
            }
        }
    }

    private func externalLink(_ name: String, _ url: URL) -> some View {
        Link(destination: url) {
            Label(name, systemImage: "arrow.up.forward.square")
        }
        .font(.callout)
        .help(url.absoluteString)
    }

    // MARK: Episodes

    @ViewBuilder private var episodeSections: some View {
        if let episode {
            let notes = episode.description ?? episode.subtitle ?? ""
            if !notes.isEmpty {
                Divider()
                section("Show Notes") {
                    ShowNotesView(html: notes)
                }
            }
            Divider()
            section("Episode") {
                MetadataRows(rows: [
                    ("Published", episode.publishedDate?.formatted(date: .abbreviated, time: .omitted)),
                    ("Season", episode.season),
                    ("Episode", episode.episode),
                    ("Length", durationString(player.duration)),
                ], labelWidth: 84)
            }
        } else if loadState == .loading {
            ProgressView().controlSize(.small)
        }

        if let description = meta?.description, !description.isEmpty {
            Divider()
            section("About the Show") {
                ExpandableText(text: plainText(fromHTML: description))
            }
        }
    }

    // MARK: Shared

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Details aren't available right now.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                loadState = .loading
                Task { await load() }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
    }

    // MARK: Loading

    private func load() async {
        if let episodeID {
            episode = app.cachedEpisode(itemID: itemID, episodeID: episodeID)
            if episode == nil {
                await app.loadEpisodes(itemID: itemID, quiet: true)
                episode = app.cachedEpisode(itemID: itemID, episodeID: episodeID)
            }
        }
        detail = await app.itemDetail(itemID: itemID)
        loadState = detail == nil ? .failed : .loaded

        var loaded: [AuthorDetail] = []
        for credit in (detail?.media?.metadata?.authors ?? []).prefix(3) {
            guard let id = credit.id, let author = await app.authorDetail(id: id) else { continue }
            loaded.append(author)
        }
        authors = loaded
    }
}

/// "Chapter 3 of 35 · 27 hr 4 min left". Its own view so the twice-a-second
/// playhead updates re-render this line, not the whole inspector.
private struct NowPlayingProgressLine: View {
    @Environment(PlayerEngine.self) private var player

    var body: some View {
        Text(summary)
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    private var summary: String {
        var parts: [String] = []
        if let index = player.currentChapterIndex {
            parts.append("Chapter \(index + 1) of \(player.chapters.count)")
        }
        let remaining = max(0, player.duration - player.currentTime)
        parts.append(durationString(remaining).map { "\($0) left" } ?? "Almost done")
        return parts.joined(separator: " · ")
    }
}

/// Chapters of the playing book. Collapsed, it shows a short window around the
/// current chapter; Show All lists every chapter and scrolls to the current one.
private struct ChapterSection: View {
    @Environment(PlayerEngine.self) private var player
    let accent: Color
    let scrollTo: (String) -> Void

    @State private var showAll = false
    private static let windowSize = 6

    var body: some View {
        let chapters = player.chapters
        let current = player.currentChapterIndex

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Chapters").font(.headline)
                Text("\(chapters.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if chapters.count > Self.windowSize {
                    Button(showAll ? "Show Less" : "Show All") {
                        showAll.toggle()
                        if showAll, let current { scrollTo(Self.rowID(current)) }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }

            LazyVStack(spacing: 2) {
                ForEach(visible(chapters, current: current)) { chapter in
                    ChapterRow(number: chapter.id + 1,
                               title: chapter.title,
                               start: chapter.start,
                               isCurrent: chapter.id == current,
                               isPlayed: current.map { chapter.id < $0 } ?? false,
                               accent: accent) {
                        player.seek(to: chapter.start)
                    }
                    .id(Self.rowID(chapter.id))
                }
            }
            .padding(.horizontal, -10)   // rows carry their own inset; align text with the headings
        }
    }

    private static func rowID(_ index: Int) -> String { "chapter-\(index)" }

    /// One chapter of context before the current one, the rest after.
    private func visible(_ chapters: [PlayerEngine.Chapter], current: Int?) -> ArraySlice<PlayerEngine.Chapter> {
        guard !showAll, chapters.count > Self.windowSize else { return chapters[...] }
        let end = min(chapters.count, max(0, (current ?? 0) - 1) + Self.windowSize)
        return chapters[max(0, end - Self.windowSize)..<end]
    }
}

/// Author photo, name, a jump into the library, and a clamped bio.
private struct AuthorBlurb: View {
    @Environment(AppState.self) private var app
    let author: AuthorDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                avatar
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.callout.weight(.semibold))
                    Button("Show in Library") { app.showGroup(kind: .authors, value: name) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            ExpandableText(text: plainText(fromHTML: author.description ?? ""), lineLimit: 5)
        }
    }

    private var name: String { author.name ?? "Author" }

    @ViewBuilder private var avatar: some View {
        let initials = ZStack {
            LinearGradient(colors: Theme.placeholderColors(seed: name),
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
        }
        if author.imagePath != nil {
            RemoteImage(url: app.authorImageURL(authorID: author.id)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } fallback: {
                initials
            }
        } else {
            initials
        }
    }
}
