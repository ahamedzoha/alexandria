import SwiftUI

enum SidebarSelection: Hashable {
    case home
    case library(String)
    case authors
    case series
    case narrators
    case stats
}

struct MainView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @State private var showAddServer = false
    @State private var searchSelection: LibraryItem?
    @State private var highlightedIndex = 0
    @State private var searchFocusTrigger = 0
    @State private var searchBlurTrigger = 0

    var body: some View {
        @Bindable var app = app
        return NavigationSplitView {
            List(selection: sidebarSelection) {
                Section {
                    Label("Home", systemImage: "house").tag(SidebarSelection.home)
                }
                Section("Library") {
                    ForEach(app.libraries) { library in
                        Label(library.name, systemImage: icon(for: library))
                            .tag(SidebarSelection.library(library.id))
                    }
                }
                Section("Browse") {
                    // Book-only groupings; podcasts have no authors/series/narrators.
                    if !selectedLibraryIsPodcast {
                        Label("Authors", systemImage: "person").tag(SidebarSelection.authors)
                        Label("Series", systemImage: "books.vertical").tag(SidebarSelection.series)
                        Label("Narrators", systemImage: "mic").tag(SidebarSelection.narrators)
                    }
                    Label("Stats", systemImage: "chart.bar").tag(SidebarSelection.stats)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 320)
            .safeAreaInset(edge: .bottom) { serverSwitcher }
        } detail: {
            VStack(spacing: 0) {
                if app.sidebar == .library, let label = app.groupLabel {
                    groupChip(label)
                }
                detailContent
                NowPlayingBar()
            }
            .overlay {
                // Scope the fade to the overlay only — animating the whole
                // detail made the grid behind it jump on show/hide.
                searchOverlay
                    .animation(.easeOut(duration: 0.14), value: showSearchDropdown)
            }
            .onChange(of: app.focusSearchRequested) {
                guard app.focusSearchRequested else { return }
                app.focusSearchRequested = false
                searchFocusTrigger += 1
            }
            .navigationTitle(currentTitle)
            .toolbar {
                if app.sidebar == .library {
                    ToolbarItem(placement: .navigation) {
                        Picker("View", selection: $app.viewMode) {
                            Image(systemName: "square.grid.2x2").tag(AppState.ViewMode.grid)
                            Image(systemName: "list.bullet").tag(AppState.ViewMode.list)
                        }
                        .pickerStyle(.segmented)
                        .help("Grid or list view")
                    }
                }
                ToolbarItem(placement: .principal) {
                    searchField
                }
                if app.sidebar == .library {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Sort by", selection: $app.sort) {
                                ForEach(AppState.LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Picker("Order", selection: $app.sortAscending) {
                                Label("Ascending", systemImage: "arrow.up").tag(true)
                                Label("Descending", systemImage: "arrow.down").tag(false)
                            }
                            Divider()
                            Picker("Show", selection: $app.filter) {
                                ForEach(AppState.LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .help("Sort and filter")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await app.syncNow() } } label: {
                        if app.isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .help(app.syncStatusText)
                    .disabled(app.isSyncing)
                }
            }
        }
        .sheet(isPresented: $showAddServer) {
            LoginView(isSheet: true) { showAddServer = false }
        }
        .sheet(item: $searchSelection) { item in
            ItemDetailView(item: item)
                .frame(width: item.isPodcast ? 640 : 560, height: item.isPodcast ? 760 : 680)
        }
    }

    // Shows the global search results dropdown on non-library pages. On the
    // library page the grid itself filters, so no dropdown is needed there.
    private var showSearchDropdown: Bool {
        app.sidebar != .library
            && !app.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder private var searchOverlay: some View {
        if showSearchDropdown {
            ZStack(alignment: .top) {
                // Dim scrim; a click anywhere outside the dropdown dismisses.
                Color.primary.opacity(0.04)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { clearSearch() }

                SearchDropdown(
                    matches: app.searchMatches,
                    highlighted: clampedHighlight,
                    onSelect: { item in
                        searchSelection = item
                        clearSearch()
                    },
                    onPlay: { item in
                        playItem(item)
                        clearSearch()
                    },
                    onShowAll: {
                        app.sidebar = .library
                    }
                )
                .padding(.top, 10)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var detailContent: some View {
        ZStack {
            switch app.sidebar {
            case .home: HomeView()
            case .library: LibraryGridView()
            case .authors: PeopleGridView(kind: .authors)
            case .series: SeriesGridView()
            case .narrators: PeopleGridView(kind: .narrators)
            case .stats: StatsView()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: app.sidebar)
    }

    private func groupChip(_ label: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.callout.weight(.medium))
            Button {
                app.clearGroup()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear filter")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            SearchField(
                text: Binding(get: { app.searchText }, set: { app.searchText = $0 }),
                placeholder: "Search library",
                focusTrigger: searchFocusTrigger,
                blurTrigger: searchBlurTrigger,
                onMoveDown: { moveHighlight(1) },
                onMoveUp: { moveHighlight(-1) },
                onSubmit: { playHighlighted() },
                onCancel: { cancelSearch() }
            )
            .frame(maxWidth: .infinity)

            if app.searchText.isEmpty {
                shortcutHint
            } else {
                Button { clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search (esc)")
            }
        }
        .font(.body)
        .frame(minWidth: 320, idealWidth: 460, maxWidth: 620)
        .padding(.horizontal, 14)
        .onChange(of: app.searchText) { highlightedIndex = 0 }
    }

    private var shortcutHint: some View {
        Text("⌘F")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .help("Press ⌘F to search")
    }

    // MARK: Search dropdown keyboard nav

    private var navigableMatches: [LibraryItem] {
        Array(app.searchMatches.prefix(SearchDropdown.maxRows))
    }

    /// Highlight clamped to the current match count, so a stale index (e.g. the
    /// query shrank the list) can never point past the end.
    private var clampedHighlight: Int {
        let count = navigableMatches.count
        guard count > 0 else { return 0 }
        return min(max(highlightedIndex, 0), count - 1)
    }

    /// Returns true when the key was consumed (dropdown open + a move happened).
    private func moveHighlight(_ delta: Int) -> Bool {
        guard showSearchDropdown, !navigableMatches.isEmpty else { return false }
        highlightedIndex = min(max(highlightedIndex + delta, 0), navigableMatches.count - 1)
        return true
    }

    /// ↵ quick-plays the highlighted result (row click still opens detail).
    private func playHighlighted() -> Bool {
        guard showSearchDropdown, !navigableMatches.isEmpty else { return false }
        playItem(navigableMatches[clampedHighlight])
        clearSearch()
        return true
    }

    private func cancelSearch() -> Bool {
        if app.searchText.isEmpty {
            searchBlurTrigger += 1   // already empty — just defocus
        } else {
            clearSearch()            // clear text + defocus
        }
        return true
    }

    private func clearSearch() {
        app.searchText = ""
        highlightedIndex = 0
        // Resign the search field so a bare Space resumes play/pause control.
        searchBlurTrigger += 1
    }

    /// Quick-play a book straight from the search dropdown (prefers a local
    /// download, else a server session), mirroring the library grid.
    private func playItem(_ item: LibraryItem) {
        startPlayback(item: item, app: app, player: player)
    }

    private var serverSwitcher: some View {
        Menu {
            ForEach(app.servers) { server in
                Button {
                    Task { await app.switchServer(server.id) }
                } label: {
                    Label(server.name,
                          systemImage: server.id == app.activeServerID ? "checkmark" : "server.rack")
                }
            }
            Divider()
            Button("Add Server…", systemImage: "plus") { showAddServer = true }
            if let active = app.activeServer {
                Button("Log Out of \(active.name)", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    app.logout()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                Text(app.activeServer?.name ?? "Server").lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
        .padding(10)
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: {
                switch app.sidebar {
                case .home: return .home
                case .library: return app.selectedLibraryID.map { .library($0) }
                case .authors: return .authors
                case .series: return .series
                case .narrators: return .narrators
                case .stats: return .stats
                }
            },
            set: { selection in
                guard let selection else { return }
                switch selection {
                case .home: app.sidebar = .home
                case .library(let id):
                    app.sidebar = .library
                    app.clearGroup()
                    Task { await app.selectLibrary(id) }
                case .authors: app.sidebar = .authors
                case .series: app.sidebar = .series
                case .narrators: app.sidebar = .narrators
                case .stats: app.sidebar = .stats
                }
            }
        )
    }

    private var currentTitle: String {
        switch app.sidebar {
        case .home: return "Home"
        case .library:
            return app.libraries.first { $0.id == app.selectedLibraryID }?.name ?? "Alexandria"
        case .authors: return "Authors"
        case .series: return "Series"
        case .narrators: return "Narrators"
        case .stats: return "Stats"
        }
    }

    private func icon(for library: Library) -> String {
        library.mediaType == "podcast" ? "antenna.radiowaves.left.and.right" : "books.vertical"
    }

    private var selectedLibraryIsPodcast: Bool {
        app.libraries.first { $0.id == app.selectedLibraryID }?.mediaType == "podcast"
    }
}
