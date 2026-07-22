import SwiftUI

enum SidebarSelection: Hashable {
    case library(String)
    case authors
    case series
    case narrators
    case stats
}

struct MainView: View {
    @Environment(AppState.self) private var app
    @State private var showAddServer = false
    @State private var searchSelection: LibraryItem?

    var body: some View {
        @Bindable var app = app
        return NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("Library") {
                    ForEach(app.libraries) { library in
                        Label(library.name, systemImage: icon(for: library))
                            .tag(SidebarSelection.library(library.id))
                    }
                }
                Section("Browse") {
                    Label("Authors", systemImage: "person").tag(SidebarSelection.authors)
                    Label("Series", systemImage: "books.vertical").tag(SidebarSelection.series)
                    Label("Narrators", systemImage: "mic").tag(SidebarSelection.narrators)
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
            .overlay { searchOverlay }
            .animation(.easeInOut(duration: 0.16), value: showSearchDropdown)
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
                .frame(minWidth: 440, minHeight: 380)
        }
        .sheet(item: $searchSelection) { item in
            ItemDetailView(item: item)
                .frame(width: 560, height: 680)
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
                    .onTapGesture { app.searchText = "" }

                SearchDropdown(
                    matches: app.searchMatches,
                    onSelect: { item in
                        searchSelection = item
                        app.searchText = ""
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
        @Bindable var app = app
        return HStack(spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search books", text: $app.searchText)
                .textFieldStyle(.plain)
                .frame(width: 260)
            if !app.searchText.isEmpty {
                Button { app.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
            Spacer(minLength: 0)
        }
        .font(.body)
        .frame(maxWidth: .infinity)
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
}
