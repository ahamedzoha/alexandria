import SwiftUI

/// The Home landing page: a personal greeting + listening snapshot, a featured
/// "Continue" card, and ABS-style horizontal artwork shelves. Mounted by
/// MainView.detailContent for `.home`; MainView owns the NowPlayingBar, so this
/// view must never add its own.
struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: LibraryItem?
    @State private var appeared = false

    private let contentMaxWidth: CGFloat = 1400

    var body: some View {
        Group {
            if app.isLoading && app.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if app.items.isEmpty {
                HomeEmptyState { Task { await app.loadLibraries() } }
            } else {
                scroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selected) { item in
            ItemDetailView(item: item)
                .frame(width: item.isPodcast ? 640 : 560, height: item.isPodcast ? 760 : 680)
        }
        .task(id: app.selectedLibraryID) {
            await app.loadStats()
            await app.loadRecentItems()
            await app.refreshRecentEpisodes()
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) { appeared = true }
        }
    }

    private var scroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xl + 6) {
                section(0) {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        GreetingHeader()
                        HomeStatRow()
                    }
                    .modifier(CenteredContent(maxWidth: contentMaxWidth))
                }

                if let hero = app.heroContinueItem {
                    // Full-bleed: the hero owns its own width cap + padding so
                    // its palette wash can run edge-to-edge under the chrome.
                    section(1) {
                        HomeHeroCard(item: hero,
                                     progress: app.progress(itemID: hero.id),
                                     maxContentWidth: contentMaxWidth,
                                     onPlay: { play(hero) },
                                     onOpen: { selected = hero })
                    }
                }

                if !app.recentEpisodes.isEmpty {
                    section(2) {
                        EpisodeShelf(title: "Latest Episodes",
                                     symbol: "dot.radiowaves.left.and.right",
                                     episodes: app.recentEpisodes)
                    }
                }
                shelf(3, "Continue Listening", "headphones",
                      Array(app.continueListening.dropFirst()), .inProgress)
                shelf(4, "Discover", "sparkles", app.discoverPicks, .notStarted)
                shelf(5, "Listen Again", "arrow.counterclockwise", app.recentlyFinished, .finished)
                shelf(6, "Recently Added", "clock.badge.plus", app.recentItems, .all)
            }
            .padding(.vertical, Theme.Space.xl)
        }
    }

    @ViewBuilder
    private func shelf(_ index: Int, _ title: String, _ symbol: String,
                       _ items: [LibraryItem], _ filter: AppState.LibraryFilter) -> some View {
        if !items.isEmpty {
            section(index) {
                HomeShelf(title: title, symbol: symbol, items: items,
                          onSeeAll: { openLibrary(filter) },
                          onOpen: { selected = $0 },
                          onPlay: { play($0) })
            }
        }
    }

    // Entrance stagger: sections rise + fade in sequence, whole cascade capped
    // at 0.5s (0.35s spring + delays capped at 0.15s). Opacity-only crossfade,
    // no stagger, under Reduce Motion.
    @ViewBuilder
    private func section<V: View>(_ index: Int, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .opacity(appeared ? 1 : 0)
            .offset(y: (appeared || reduceMotion) ? 0 : 16)
            .animation(reduceMotion ? .easeOut(duration: 0.2)
                                    : .smooth(duration: 0.35).delay(min(Double(index) * 0.04, 0.15)),
                       value: appeared)
    }

    private func openLibrary(_ filter: AppState.LibraryFilter) {
        app.filter = filter
        app.clearGroup()
        app.sidebar = .library
    }

    private func play(_ item: LibraryItem) {
        startPlayback(item: item, app: app, player: player)
    }
}

/// Caps line length but LEFT-aligns the block so the greeting/stats/hero share
/// the shelves' left margin instead of floating centered on wide screens.
private struct CenteredContent: ViewModifier {
    let maxWidth: CGFloat
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.xl)
    }
}

/// Warm, inviting first-run Home for a logged-in user with an empty library.
struct HomeEmptyState: View {
    var onRefresh: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 0) {
            GreetingHeader()
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, Theme.Space.xl)

            Spacer(minLength: Theme.Space.xl)

            VStack(spacing: Theme.Space.l) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 54))
                    .foregroundStyle(.secondary)
                    .frame(width: 128, height: 128)
                    .background(
                        RadialGradient(colors: [.accentColor.opacity(0.20), .clear],
                                       center: .center, startRadius: 4, endRadius: 84),
                        in: Circle()
                    )
                    .scaleEffect(breathe && !reduceMotion ? 1.04 : 1)

                VStack(spacing: 8) {
                    Text("Nothing on your shelf yet")
                        .font(.title2.weight(.semibold))
                    Text("When your audiobookshelf server finishes scanning, your books land here — ready to play. Pull the latest anytime.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onRefresh) {
                    Label("Refresh Library", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Books you add on your server appear here automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, Theme.Space.xl)

            Spacer(minLength: Theme.Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}
