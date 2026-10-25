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

            ShelfScroller {
                ForEach(items) { item in
                    BookShelfCard(item: item,
                                  onOpen: { onOpen(item) },
                                  onPlay: { onPlay(item) })
                        .shelfCard()
                }
            }
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
            .queueDraggable(item)
    }

    @ViewBuilder private var menu: some View {
        Button("Play", systemImage: "play.fill", action: onPlay)
        QueueMenuItems(item: item)
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

            ShelfScroller(alignment: .top) {
                ForEach(entries) { entry in
                    card(for: entry).shelfCard()
                }
            }
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
                        .foregroundStyle(.secondary)
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

            ShelfScroller(alignment: .top) {
                ForEach(episodes) { episode in
                    EpisodeCard(episode: episode).shelfCard()
                }
            }
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

/// The horizontal scroller behind every Home shelf. Cards run edge to edge;
/// hovering the shelf reveals paging arrows over the artwork (as in Music),
/// so a plain mouse wheel — no trackpad, no Shift-scroll — can still reach
/// every card. VoiceOver gets the arrows whenever there's more to scroll.
struct ShelfScroller<Content: View>: View {
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: () -> Content

    private enum Direction { case back, forward }

    /// Just the numbers the arrows need, so scrolling doesn't re-render the
    /// shelf for unrelated geometry changes.
    private struct Extent: Equatable {
        var offset: CGFloat = 0
        var minOffset: CGFloat = 0
        var maxOffset: CGFloat = 0
        var width: CGFloat = 0
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition()
    @State private var extent = Extent()
    @State private var hovering = false

    /// Vertical center of a shelf card's 150pt artwork (below the 4pt inset).
    private var artworkCenter: CGFloat { 4 + ShelfCard.width / 2 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: alignment, spacing: Theme.Space.m) {
                content()
            }
            .padding(.vertical, 4)
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Extent.self) { geo in
            Extent(offset: geo.contentOffset.x,
                   minOffset: -geo.contentInsets.leading,
                   maxOffset: max(-geo.contentInsets.leading,
                                  geo.contentSize.width + geo.contentInsets.trailing - geo.containerSize.width),
                   width: geo.containerSize.width)
        } action: { _, new in
            extent = new
        }
        .scrollClipDisabled()
        // Draw past the bounds (hover lift, shadows) vertically only; covers
        // must stop at the column's sides, not slide under the inspector.
        .mask { Rectangle().padding(.vertical, -Theme.Space.xl) }
        .contentMargins(.horizontal, Theme.Space.xl, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .horizontal)
        .overlay(alignment: .topLeading) { arrow(.back) }
        .overlay(alignment: .topTrailing) { arrow(.forward) }
        .onHover { hovering = $0 }
    }

    private func canScroll(_ direction: Direction) -> Bool {
        switch direction {
        case .back: extent.offset > extent.minOffset + 1
        case .forward: extent.offset < extent.maxOffset - 1
        }
    }

    private func arrow(_ direction: Direction) -> some View {
        let available = canScroll(direction)
        let shown = available && hovering
        return Button { page(direction) } label: {
            Image(systemName: direction == .back ? "chevron.left" : "chevron.right")
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .padding(.horizontal, Theme.Space.s)
        .offset(y: artworkCenter - 16)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .animation(.easeOut(duration: 0.15), value: shown)
        .help(direction == .back ? "Scroll Back" : "Scroll Forward")
        .accessibilityLabel(direction == .back ? "Scroll Back" : "Scroll Forward")
        .accessibilityHidden(!available)
    }

    /// Most of a viewport per click, keeping a card of overlap for context.
    private func page(_ direction: Direction) {
        let step = max(extent.width - ShelfCard.width - Theme.Space.m * 2, ShelfCard.width)
        let target = direction == .back ? extent.offset - step : extent.offset + step
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) {
            position.scrollTo(x: min(max(target, extent.minOffset), extent.maxOffset))
        }
    }
}

/// Fixed card width + the gentle edge falloff every shelf card shares.
private struct ShelfCard: ViewModifier {
    static let width: CGFloat = 150

    func body(content: Content) -> some View {
        content
            .frame(width: Self.width)
            .scrollTransition { content, phase in
                content
                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
                    .opacity(phase.isIdentity ? 1 : 0.85)
            }
    }
}

private extension View {
    func shelfCard() -> some View { modifier(ShelfCard()) }
}
