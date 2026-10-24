import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    struct ItemProgress: Sendable {
        var fraction: Double
        var isFinished: Bool
        var lastUpdate: Double = 0   // epoch ms of the last progress update
    }

    // Progress is keyed per item + episode (episodeID nil for book/item-level).
    struct ProgressKey: Hashable { let itemID: String; let episodeID: String? }

    /// An in-progress podcast episode resolved to its owning show, ready for
    /// the Home continue surfaces (hero + Continue Listening shelf). Progress
    /// itself is looked up live in `progressByItem` — this only carries the
    /// metadata that needs async resolution.
    struct EpisodeResume: Identifiable, Sendable {
        let episode: PodcastEpisode
        let item: LibraryItem
        var id: String { "\(item.id)|\(episode.id)" }
    }

    struct ServerRef: Codable, Identifiable, Sendable {
        let id: String
        var name: String
        var url: String
    }

    enum LibrarySort: String, CaseIterable, Identifiable {
        case title = "Title"
        case author = "Author"
        case progress = "Progress"
        var id: String { rawValue }
    }

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case inProgress = "In Progress"
        case finished = "Finished"
        case notStarted = "Not Started"
        case downloaded = "Downloaded"
        var id: String { rawValue }
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case grid, list
        var id: String { rawValue }
    }

    // Sidebar sections / browse grouping
    enum Browse: Hashable, Sendable {
        case home
        case library
        case authors
        case series
        case narrators
        case stats
    }

    // Servers (tokens live in UserDefaults, keyed by server id — see tokenKey).
    // TODO: move tokens to the Keychain once Developer ID signing lands.
    var servers: [ServerRef] = []
    var activeServerID: String?

    // Library data
    var libraries: [Library] = []
    var selectedLibraryID: String?
    var items: [LibraryItem] = []
    var recentItems: [LibraryItem] = []   // newest-added, for the Home shelf
    var progressByItem: [ProgressKey: ItemProgress] = [:]
    // Podcast episode lists, keyed by library item id (nil until loaded).
    var episodesByItem: [String: [PodcastEpisode]] = [:]
    // Items whose last loadEpisodes fetch failed, so the episode list UI can
    // show a retry state. Cleared when a (re)load succeeds.
    var episodesLoadFailed: Set<String> = []
    // Latest episodes across podcast libraries as fetched from the server.
    // HomeData's `recentEpisodes` filters these for the Home shelf.
    var fetchedRecentEpisodes: [PodcastEpisode] = []
    // In-progress podcast episodes resolved to (episode, show) pairs, most
    // recently played first. Rebuilt by refreshEpisodeResumes(); consumers
    // re-derive progress/ordering live from `progressByItem`, so entries here
    // can't go stale between refreshes — only appear/disappear.
    var episodeResumes: [EpisodeResume] = []
    // Collapses overlapping refreshEpisodeResumes calls (sync loop + playback
    // ticks): one pass runs at a time, and a call arriving mid-pass queues
    // exactly one follow-up pass so fresher progress is never dropped.
    @ObservationIgnored private var episodeResumeRefreshInFlight = false
    @ObservationIgnored private var episodeResumeRefreshQueued = false
    // Progress rows that failed to resolve (episode/show deleted server-side),
    // keyed by "item|episode|lastUpdate". Skipped on later refreshes so one
    // stale row can't refetch its show's episode list every 45s sync; the row
    // is retried if it updates again (lastUpdate changes the key).
    @ObservationIgnored private var unresolvedResumeRows: Set<String> = []
    let downloads = DownloadStore()
    // Items fetched individually via resolveItem (auto-play/next-episode
    // targets that aren't in `items` or `recentItems`), keyed by id.
    @ObservationIgnored private var itemsByID: [String: LibraryItem] = [:]
    // In-flight server progress write per (item, episode) — see enqueueProgressPatch.
    @ObservationIgnored private var progressPatchTasks: [ProgressKey: Task<Void, Never>] = [:]
    // Background 45s sync loop + app-activation observer (see startSyncLoop).
    @ObservationIgnored private var syncLoopTask: Task<Void, Never>?
    @ObservationIgnored private var didBecomeActiveObserver: (any NSObjectProtocol)?
    var isLoading = false
    var errorMessage: String?

    // Sync (pull progress from the server so other devices reflect quickly)
    var isSyncing = false
    var lastSyncedAt: Date?

    // Search / sort / filter / browse
    var searchText = ""
    // Toggled by the Find (⌘F) menu command; MainView focuses the field.
    var focusSearchRequested = false
    var sort: LibrarySort = .title
    var sortAscending = true
    var filter: LibraryFilter = .all
    var viewMode: ViewMode = .grid
    var sidebar: Browse = .home
    // When an episode finishes, start the next unfinished one automatically.
    var autoPlayNextEpisodes: Bool = UserDefaults.standard.object(forKey: "autoPlayNextEpisodes") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPlayNextEpisodes, forKey: "autoPlayNextEpisodes") }
    }
    // The trailing Now Playing inspector; remembered across launches.
    var showNowPlayingInfo: Bool = UserDefaults.standard.bool(forKey: "showNowPlayingInfo") {
        didSet { UserDefaults.standard.set(showNowPlayingInfo, forKey: "showNowPlayingInfo") }
    }
    var groupKind: Browse?
    var groupValue: String?
    var stats: LibraryStats?
    var authors: [AuthorRef] = []
    // Expanded item + author records for the detail sheet and the Now Playing
    // inspector, kept for the session so reopening either is instant.
    @ObservationIgnored private var itemDetailCache: [String: ItemDetail] = [:]
    @ObservationIgnored private var authorDetailCache: [String: AuthorDetail] = [:]

    init() {
        loadServers()
        CoverCache.shared.authToken = token
        if isLoggedIn { startSyncLoop() }
    }

    // MARK: Active server

    var activeServer: ServerRef? { servers.first { $0.id == activeServerID } }
    var serverURL: String { activeServer?.url ?? "" }
    var token: String? {
        guard let id = activeServerID else { return nil }
        return UserDefaults.standard.string(forKey: tokenKey(id))
    }
    var isLoggedIn: Bool { activeServer != nil && !(token ?? "").isEmpty }

    // Token lives in the app's sandbox container (private to this app). Keychain
    // needs a signing-team entitlement to work on ad-hoc dev builds, so we defer it.
    private func tokenKey(_ id: String) -> String { "token_\(id)" }

    private var api: APIClient { APIClient(serverURL: serverURL, token: token) }

    // MARK: Visible items

    var visibleItems: [LibraryItem] {
        var result = items

        if let value = groupValue, let kind = groupKind {
            switch kind {
            case .authors: result = result.filter { $0.author.localizedCaseInsensitiveContains(value) }
            case .narrators: result = result.filter { ($0.narrator ?? "").localizedCaseInsensitiveContains(value) }
            case .series: result = result.filter { $0.seriesBaseName == value }
            case .library, .stats, .home: break
            }
        }

        switch filter {
        case .all:
            break
        case .inProgress:
            // Podcasts have no item-level progress row — a show is in
            // progress when any of its episodes is. Keeps the Continue
            // shelf's See All destination from landing on an empty page.
            result = result.filter { item in
                if item.isPodcast {
                    return progressByItem.contains { key, p in
                        key.itemID == item.id && key.episodeID != nil
                            && p.fraction > 0.001 && !p.isFinished
                    }
                }
                let p = progress(itemID: item.id)
                return (p?.fraction ?? 0) > 0.001 && !(p?.isFinished ?? false)
            }
        case .finished:
            result = result.filter { progress(itemID: $0.id)?.isFinished ?? false }
        case .notStarted:
            result = result.filter { (progress(itemID: $0.id)?.fraction ?? 0) <= 0.001 }
        case .downloaded:
            // A podcast counts as downloaded when any of its episodes is.
            result = result.filter { item in
                item.isPodcast
                    ? downloads.downloadedBooks.contains { $0.itemID == item.id }
                    : downloads.isDownloaded(item.id)
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query) || $0.author.lowercased().contains(query)
            }
        }

        switch sort {
        case .title:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author:
            result.sort { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        case .progress:
            result.sort { (progress(itemID: $0.id)?.fraction ?? 0) < (progress(itemID: $1.id)?.fraction ?? 0) }
        }
        if !sortAscending { result.reverse() }

        return result
    }

    /// Pure title/author match over the loaded library, used by the global
    /// search dropdown on non-library pages. Ignores group/filter/sort so the
    /// dropdown always reflects the raw query.
    var searchMatches: [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return items
            .filter { $0.title.lowercased().contains(query) || $0.author.lowercased().contains(query) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Servers / auth

    func addServer(name: String, url: String, username: String, password: String) async -> Bool {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let t = try await APIClient(serverURL: cleaned, token: nil)
                .login(username: username, password: password)
            let id = UUID().uuidString
            // Reuse an existing server for the same URL instead of duplicating it.
            if let existing = servers.first(where: { $0.url == cleaned }) {
                UserDefaults.standard.set(t, forKey: tokenKey(existing.id))
                activeServerID = existing.id
            } else {
                let trimmedName = name.trimmingCharacters(in: .whitespaces)
                let displayName = trimmedName.isEmpty ? hostName(cleaned) : trimmedName
                UserDefaults.standard.set(t, forKey: tokenKey(id))
                servers.append(ServerRef(id: id, name: displayName, url: cleaned))
                activeServerID = id
            }
            persistServers()
            CoverCache.shared.authToken = token
            resetLibraryState()
            startSyncLoop()
            await loadLibraries()
            return true
        } catch {
            errorMessage = friendly(error)
            return false
        }
    }

    func switchServer(_ id: String) async {
        guard id != activeServerID, servers.contains(where: { $0.id == id }) else { return }
        activeServerID = id
        persistServers()
        CoverCache.shared.authToken = token
        resetLibraryState()
        startSyncLoop()
        await loadLibraries()
    }

    func removeServer(_ id: String) {
        UserDefaults.standard.removeObject(forKey: tokenKey(id))
        servers.removeAll { $0.id == id }
        if activeServerID == id { activeServerID = servers.first?.id }
        persistServers()
        CoverCache.shared.authToken = token
        resetLibraryState()
        if activeServerID != nil {
            Task { await loadLibraries() }
        } else {
            stopSyncLoop()
        }
    }

    func logout() {
        if let id = activeServerID { removeServer(id) }
    }

    private func resetLibraryState() {
        libraries = []
        items = []
        recentItems = []
        progressByItem = [:]
        episodesByItem = [:]
        episodesLoadFailed = []
        fetchedRecentEpisodes = []
        episodeResumes = []
        unresolvedResumeRows = []
        itemsByID = [:]
        itemDetailCache = [:]
        authorDetailCache = [:]
        selectedLibraryID = nil
        searchText = ""
        groupKind = nil
        groupValue = nil
        sidebar = .home
        errorMessage = nil
    }

    private func loadServers() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "servers"),
           let list = try? JSONDecoder().decode([ServerRef].self, from: data) {
            servers = list
        }
        activeServerID = defaults.string(forKey: "activeServerID")

        // Migrate legacy single-server storage (url + token in UserDefaults).
        if servers.isEmpty,
           let url = defaults.string(forKey: "serverURL"),
           let legacyToken = defaults.string(forKey: "token"),
           !url.isEmpty, !legacyToken.isEmpty {
            let id = UUID().uuidString
            UserDefaults.standard.set(legacyToken, forKey: tokenKey(id))
            servers = [ServerRef(id: id, name: hostName(url), url: url)]
            activeServerID = id
            persistServers()
            defaults.removeObject(forKey: "serverURL")
            defaults.removeObject(forKey: "token")
        }

        // Clean up any duplicate servers (same URL) left by earlier builds.
        // Keep the active server's entry (its token is the valid one).
        if let active = activeServerID, let idx = servers.firstIndex(where: { $0.id == active }) {
            let a = servers.remove(at: idx)
            servers.insert(a, at: 0)
        }
        var seenURLs = Set<String>()
        var deduped: [ServerRef] = []
        for server in servers {
            if seenURLs.contains(server.url) {
                UserDefaults.standard.removeObject(forKey: tokenKey(server.id))
            } else {
                seenURLs.insert(server.url)
                deduped.append(server)
            }
        }
        if deduped.count != servers.count {
            servers = deduped
            if let active = activeServerID, !servers.contains(where: { $0.id == active }) {
                activeServerID = servers.first?.id
            }
            persistServers()
        }

        if activeServerID == nil { activeServerID = servers.first?.id }
    }

    private func persistServers() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: "servers")
        }
        defaults.set(activeServerID, forKey: "activeServerID")
    }

    private func hostName(_ url: String) -> String {
        URLComponents(string: url)?.host ?? url
    }

    // MARK: Library loading

    func loadLibraries() async {
        errorMessage = nil
        do {
            libraries = try await api.libraries()
            if selectedLibraryID == nil { selectedLibraryID = libraries.first?.id }
            await loadProgress()
            await refreshRecentEpisodes()
            // After loadItems: the grid content lands first (no empty-state
            // flash while resumes resolve), and resolveItem then finds shows
            // in the just-loaded items for free.
            if let id = selectedLibraryID { await loadItems(libraryID: id) }
            await refreshEpisodeResumes()
        } catch {
            errorMessage = friendly(error)
        }
    }

    /// Pull latest progress from the server + flush any queued local progress.
    func syncNow() async {
        guard isLoggedIn, !isSyncing else { return }
        isSyncing = true
        await downloads.flushPending(api: api)
        await loadProgress()
        await refreshRecentEpisodes()
        await refreshEpisodeResumes()
        lastSyncedAt = Date()
        isSyncing = false
    }

    var syncStatusText: String {
        if isSyncing { return "Syncing…" }
        guard let date = lastSyncedAt else { return "Not synced yet" }
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 5 { return "Synced just now" }
        if secs < 60 { return "Synced \(secs)s ago" }
        let mins = secs / 60
        if mins < 60 { return "Synced \(mins)m ago" }
        return "Synced \(mins / 60)h ago"
    }

    /// Background refresh: pull progress from the server every 45s while the
    /// app runs, plus once whenever the app becomes active. Owned here rather
    /// than by a view so window churn can't duplicate or drop it.
    func startSyncLoop() {
        guard syncLoopTask == nil else { return }   // already running
        syncLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled, let self else { return }
                if self.isLoggedIn { await self.syncNow() }
            }
        }
        if didBecomeActiveObserver == nil {
            didBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isLoggedIn else { return }
                    Task { await self.syncNow() }
                }
            }
        }
    }

    func stopSyncLoop() {
        syncLoopTask?.cancel()
        syncLoopTask = nil
    }

    func loadProgress() async {
        guard let list = try? await api.mediaProgress() else { return }
        var map: [ProgressKey: ItemProgress] = [:]
        for entry in list {
            guard let id = entry.libraryItemId else { continue }
            map[ProgressKey(itemID: id, episodeID: entry.episodeId)] =
                ItemProgress(fraction: entry.progress ?? 0,
                             isFinished: entry.isFinished ?? false,
                             lastUpdate: entry.lastUpdate ?? 0)
        }
        progressByItem = map
    }

    /// Progress lookup: nil episodeID reads the item-level (book) entry;
    /// podcast episode progress lives under (itemID, episodeID).
    func progress(itemID: String, episodeID: String? = nil) -> ItemProgress? {
        progressByItem[ProgressKey(itemID: itemID, episodeID: episodeID)]
    }

    func selectLibrary(_ id: String) async {
        guard id != selectedLibraryID else { return }
        selectedLibraryID = id
        groupKind = nil
        groupValue = nil
        await loadItems(libraryID: id)
    }

    func loadItems(libraryID: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await api.items(libraryID: libraryID)
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: Browse

    func showGroup(kind: Browse, value: String) {
        groupKind = kind
        groupValue = value
        sidebar = .library
    }

    func clearGroup() {
        groupKind = nil
        groupValue = nil
    }

    var groupLabel: String? {
        guard let value = groupValue, let kind = groupKind else { return nil }
        switch kind {
        case .authors: return "Author · \(value)"
        case .narrators: return "Narrator · \(value)"
        case .series: return "Series · \(value)"
        case .library, .stats, .home: return nil
        }
    }

    // MARK: Playback support

    func coverURL(itemID: String) -> URL? {
        api.coverURL(itemID: itemID)
    }

    func itemDetail(itemID: String) async -> ItemDetail? {
        if let cached = itemDetailCache[itemID] { return cached }
        let server = activeServerID
        guard let detail = try? await api.itemDetail(itemID: itemID) else { return nil }
        // A response that lands after a server switch belongs to the old server.
        guard activeServerID == server else { return nil }
        itemDetailCache[itemID] = detail
        return detail
    }

    func authorDetail(id: String) async -> AuthorDetail? {
        if let cached = authorDetailCache[id] { return cached }
        let server = activeServerID
        guard let author = try? await api.author(id: id) else { return nil }
        guard activeServerID == server else { return nil }
        authorDetailCache[id] = author
        return author
    }

    func loadStats() async {
        guard let id = selectedLibraryID ?? libraries.first?.id else { return }
        stats = try? await api.libraryStats(libraryID: id)
    }

    /// Newest-added items for the Home "Recently Added" shelf (server-sorted by
    /// addedAt, which the default title-sorted `items` fetch can't provide).
    func loadRecentItems() async {
        guard let id = selectedLibraryID ?? libraries.first?.id else { return }
        recentItems = (try? await api.recentlyAdded(libraryID: id, limit: 20)) ?? []
    }

    func loadAuthors() async {
        guard let id = selectedLibraryID ?? libraries.first?.id else { return }
        authors = (try? await api.authors(libraryID: id)) ?? []
    }

    func authorImageURL(authorID: String) -> URL? {
        api.authorImageURL(authorID: authorID)
    }

    /// How many library items credit this author (substring match handles
    /// multi-author strings like "Neil Gaiman, Dirk Maggs").
    func bookCount(forAuthor name: String) -> Int {
        items.filter { $0.author.localizedCaseInsensitiveContains(name) }.count
    }

    func playSession(itemID: String, episodeID: String? = nil) async -> PlaybackInfo? {
        do {
            return try await api.play(itemID: itemID, episodeID: episodeID)
        } catch {
            errorMessage = friendly(error)
            return nil
        }
    }

    func reportProgress(itemID: String, episodeID: String?, time: Double, duration: Double) {
        let fraction = duration > 0 ? min(1, time / duration) : 0
        let key = ProgressKey(itemID: itemID, episodeID: episodeID)
        progressByItem[key] =
            ItemProgress(fraction: fraction,
                         isFinished: fraction >= 0.99,
                         lastUpdate: Date().timeIntervalSince1970 * 1000)
        downloads.saveProgress(itemID: itemID, episodeID: episodeID, currentTime: time, duration: duration)

        // A just-started episode isn't in episodeResumes yet — resolve it so
        // the Home continue surfaces pick it up immediately. Gated on the
        // episode being present in a local cache: when it isn't (offline
        // playback of a download after relaunch, or a feed-pruned episode),
        // a refresh could never resolve it either, and the per-tick calls
        // would retry the network for the whole listening session. Finished
        // rows are skipped — they can only drop entries, which the live
        // continueQueue filter already does.
        if let episodeID,
           let p = progressByItem[key], !p.isFinished,
           !episodeResumes.contains(where: { $0.item.id == itemID && $0.episode.id == episodeID }),
           episodesByItem[itemID]?.contains(where: { $0.id == episodeID }) == true
               || fetchedRecentEpisodes.contains(where: { $0.libraryItemId == itemID && $0.id == episodeID }) {
            Task { await refreshEpisodeResumes() }
        }

        enqueueProgressPatch(for: key) { [weak self] in
            guard let self else { return }
            do {
                try await self.api.patchProgress(itemID: itemID, episodeID: episodeID,
                                                 currentTime: time, duration: duration,
                                                 progress: fraction, isFinished: fraction >= 0.99)
                await self.downloads.flushPending(api: self.api)
            } catch {
                guard !Task.isCancelled else { return }   // superseded by a newer write
                self.downloads.queuePending(itemID: itemID, episodeID: episodeID, currentTime: time, duration: duration)
            }
        }
    }

    /// Serialize server progress writes per (item, episode): the newest write
    /// cancels the previous one and waits for it to wind down before sending,
    /// so PATCHes for the same key can't land out of order (latest wins).
    private func enqueueProgressPatch(for key: ProgressKey, _ patch: @escaping @MainActor () async -> Void) {
        let previous = progressPatchTasks[key]
        previous?.cancel()
        progressPatchTasks[key] = Task {
            _ = await previous?.value
            guard !Task.isCancelled else { return }
            await patch()
        }
    }

    func flushPendingProgress() async {
        await downloads.flushPending(api: api)
    }

    // MARK: Podcasts

    /// Cached episode list for a podcast item; nil until loadEpisodes has run.
    func episodes(for itemID: String) -> [PodcastEpisode]? {
        episodesByItem[itemID]
    }

    /// One episode from whatever is already in memory: the show's loaded
    /// list, the recent-episodes feed, or the resolved continue entries.
    func cachedEpisode(itemID: String, episodeID: String) -> PodcastEpisode? {
        episodesByItem[itemID]?.first { $0.id == episodeID }
            ?? fetchedRecentEpisodes.first { $0.libraryItemId == itemID && $0.id == episodeID }
            ?? episodeResumes.first { $0.item.id == itemID && $0.episode.id == episodeID }?.episode
    }

    /// Fetch the expanded item and cache its episode list, merging the
    /// response's progress rows (include=progress) into `progressByItem` so
    /// episode state is current even before the next /api/me sync. Failures
    /// are recorded in `episodesLoadFailed` so the episode UI can offer retry;
    /// `quiet` skips the user-facing error for background refreshes (a stale
    /// progress row must not raise an alert on every sync).
    func loadEpisodes(itemID: String, quiet: Bool = false) async {
        do {
            let expanded = try await api.fetchItemExpanded(itemID: itemID)
            episodesByItem[itemID] = expanded.episodes
            episodesLoadFailed.remove(itemID)
            for entry in expanded.userMediaProgress ?? [] {
                let key = ProgressKey(itemID: itemID, episodeID: entry.episodeId)
                let incoming = ItemProgress(fraction: entry.progress ?? 0,
                                            isFinished: entry.isFinished ?? false,
                                            lastUpdate: entry.lastUpdate ?? 0)
                // Don't clobber a newer local (optimistic) update with a stale row.
                if let existing = progressByItem[key], existing.lastUpdate > incoming.lastUpdate { continue }
                progressByItem[key] = incoming
            }
        } catch {
            // Background (quiet) passes leave no user-facing traces: flagging
            // episodesLoadFailed here would show a "Couldn't Load Episodes"
            // retry state for a show the user never opened, off a server blip
            // they never saw.
            guard !quiet else { return }
            episodesLoadFailed.insert(itemID)
            errorMessage = friendly(error)
        }
    }

    /// Episode-level progress rows worth resuming (started, unfinished) as
    /// (itemID, episodeID) pairs, most recently played first, capped. Static
    /// and pure over the progress map so the selection is unit-testable
    /// without constructing an AppState.
    static func episodeResumeCandidates(
        in progress: [ProgressKey: ItemProgress], limit: Int = 12
    ) -> [(itemID: String, episodeID: String)] {
        progress
            .compactMap { key, p -> (String, String, Double)? in
                guard let episodeID = key.episodeID,
                      p.fraction > 0.001, !p.isFinished else { return nil }
                return (key.itemID, episodeID, p.lastUpdate)
            }
            .sorted { $0.2 > $1.2 }
            .prefix(limit)
            .map { (itemID: $0.0, episodeID: $0.1) }
    }

    /// Rebuild `episodeResumes`: resolve each in-progress episode row to its
    /// episode + owning show. Already-resolved entries are reused verbatim
    /// (metadata doesn't change), then local caches (episodesByItem,
    /// fetchedRecentEpisodes); only a full cache miss fetches the show's
    /// episode list, quietly. Rows that no longer resolve (episode or show
    /// deleted server-side) are skipped, never surfaced as errors. A call
    /// arriving while a pass is in flight queues one follow-up pass, so a
    /// refresh triggered by fresher progress is never silently dropped.
    func refreshEpisodeResumes() async {
        guard episodeResumeRefreshInFlight == false else {
            episodeResumeRefreshQueued = true
            return
        }
        episodeResumeRefreshInFlight = true
        defer { episodeResumeRefreshInFlight = false }
        repeat {
            episodeResumeRefreshQueued = false
            await runEpisodeResumePass()
        } while episodeResumeRefreshQueued
    }

    private func runEpisodeResumePass() async {
        let server = activeServerID
        var resolved: [EpisodeResume] = []
        for (itemID, episodeID) in Self.episodeResumeCandidates(in: progressByItem) {
            // Bail the moment the account changes: later iterations would fire
            // the old server's item IDs at the new server's API.
            guard server == activeServerID else { return }

            // Sticky: a previously resolved entry survives transient fetch
            // failures (offline sync, server blip) instead of vanishing from
            // the hero/shelf until some later pass re-resolves it.
            if let existing = episodeResumes.first(where: { $0.item.id == itemID && $0.episode.id == episodeID }) {
                resolved.append(existing)
                continue
            }

            let stamp = progressByItem[ProgressKey(itemID: itemID, episodeID: episodeID)]?.lastUpdate ?? 0
            let rowKey = "\(itemID)|\(episodeID)|\(stamp)"
            guard !unresolvedResumeRows.contains(rowKey) else { continue }

            var episode = episodesByItem[itemID]?.first { $0.id == episodeID }
                ?? fetchedRecentEpisodes.first { $0.libraryItemId == itemID && $0.id == episodeID }
            if episode == nil {
                await loadEpisodes(itemID: itemID, quiet: true)
                // Fetch failed (offline, server blip): retry next sync rather
                // than tombstoning — a transient failure is not a deletion.
                guard episodesByItem[itemID] != nil else { continue }
                episode = episodesByItem[itemID]?.first { $0.id == episodeID }
            }
            guard let episode else {
                // List is fresh and the episode isn't in it — genuinely gone
                // (feed-pruned). Tombstone so it doesn't refetch every sync.
                unresolvedResumeRows.insert(rowKey)
                continue
            }
            // resolveItem misses are treated as transient too (retry next sync).
            guard let item = await resolveItem(id: itemID) else { continue }
            resolved.append(EpisodeResume(episode: episode, item: item))
        }
        // A server switch mid-resolution means these entries belong to the
        // previous account — drop them; the new server's sync rebuilds.
        guard server == activeServerID else { return }
        episodeResumes = resolved
    }

    /// Latest episodes across every podcast library, as fetched. HomeData's
    /// `recentEpisodes` filters + re-orders these for the Home shelf. On a
    /// flaky refresh the previous list is kept — only successful fetches
    /// overwrite it, and if every library fails the shelf keeps its content.
    func refreshRecentEpisodes() async {
        let podcastLibraries = libraries.filter { $0.mediaType == "podcast" }
        guard !podcastLibraries.isEmpty else {
            fetchedRecentEpisodes = []
            return
        }
        var merged: [PodcastEpisode] = []
        var anySucceeded = false
        for library in podcastLibraries {
            do {
                let response = try await api.fetchRecentEpisodes(libraryID: library.id, limit: 15)
                merged.append(contentsOf: response.episodes)
                anySucceeded = true
            } catch {
                print("[Alexandria] recent episodes fetch failed for library \(library.id): \(error)")
            }
        }
        if anySucceeded { fetchedRecentEpisodes = merged }
    }

    /// Mark an episode (un)finished: optimistic local update, then the server
    /// PATCH. Offline, the mark is queued as pending progress carrying the
    /// isFinished flag, so it flushes even when the duration is unknown.
    func markEpisode(itemID: String, episodeID: String, finished: Bool) {
        progressByItem[ProgressKey(itemID: itemID, episodeID: episodeID)] =
            ItemProgress(fraction: finished ? 1 : 0,
                         isFinished: finished,
                         lastUpdate: Date().timeIntervalSince1970 * 1000)
        Task {
            do {
                if finished {
                    try await api.markFinished(itemID: itemID, episodeID: episodeID)
                } else {
                    try await api.patchProgress(itemID: itemID, episodeID: episodeID,
                                                progress: 0, isFinished: false)
                }
                await downloads.flushPending(api: api)
            } catch {
                let duration = episodes(for: itemID)?.first(where: { $0.id == episodeID })?.bestDuration ?? 0
                downloads.queuePending(itemID: itemID, episodeID: episodeID,
                                       currentTime: finished ? duration : 0, duration: duration,
                                       isFinished: finished)
            }
        }
    }

    /// Next unfinished episode after the given one, in feed order (oldest →
    /// newest, same `sortDate` key as EpisodeListView), so episodic shows
    /// advance chronologically. Finished episodes are skipped.
    func nextEpisode(after episodeID: String, in itemID: String) -> PodcastEpisode? {
        guard let list = episodesByItem[itemID] else { return nil }
        let ordered = list.sorted { $0.sortDate < $1.sortDate }
        guard let index = ordered.firstIndex(where: { $0.id == episodeID }) else { return nil }
        return ordered.dropFirst(index + 1).first {
            !(progress(itemID: itemID, episodeID: $0.id)?.isFinished ?? false)
        }
    }

    /// The episode an item-level "play" targets for a podcast: the in-progress
    /// episode played most recently, else the next unfinished episode (feed
    /// order) after the last finished one, else the newest. Loads the episode
    /// list on a cache miss; nil when no episodes are available.
    func resumeEpisode(for item: LibraryItem) async -> PodcastEpisode? {
        if episodesByItem[item.id] == nil { await loadEpisodes(itemID: item.id) }
        guard let list = episodesByItem[item.id], !list.isEmpty else { return nil }
        func progressFor(_ episode: PodcastEpisode) -> ItemProgress? {
            progress(itemID: item.id, episodeID: episode.id)
        }
        let inProgress = list.filter {
            guard let p = progressFor($0) else { return false }
            return p.fraction > 0 && p.fraction < 1 && !p.isFinished
        }
        if let resume = inProgress.max(by: {
            (progressFor($0)?.lastUpdate ?? 0) < (progressFor($1)?.lastUpdate ?? 0)
        }) {
            return resume
        }
        let ordered = list.sorted { $0.sortDate < $1.sortDate }
        if let lastFinished = ordered.lastIndex(where: { progressFor($0)?.isFinished ?? false }),
           let next = ordered.dropFirst(lastFinished + 1).first(where: {
               !(progressFor($0)?.isFinished ?? false)
           }) {
            return next
        }
        return ordered.last
    }

    func item(byID id: String) -> LibraryItem? {
        items.first { $0.id == id } ?? recentItems.first { $0.id == id }
    }

    /// Item lookup that can reach the server: loaded lists first, then the
    /// side cache, then GET api/items/{id} (cached for later calls). Used by
    /// surfaces that only know an id (Home episode cards, auto-play-next).
    func resolveItem(id: String) async -> LibraryItem? {
        if let loaded = item(byID: id) { return loaded }
        if let cached = itemsByID[id] { return cached }
        guard let fetched = try? await api.item(itemID: id) else { return nil }
        itemsByID[id] = fetched
        return fetched
    }

    // MARK: Downloads

    /// Pass an episode to download just that episode; nil downloads the book —
    /// or, for podcasts, the resume-target episode (an item-level play session
    /// isn't valid for podcasts).
    func startDownload(item: LibraryItem, episode: PodcastEpisode? = nil) async {
        var episode = episode
        if item.isPodcast, episode == nil {
            guard let target = await resumeEpisode(for: item) else { return }
            episode = target
        }
        let episodeID = episode?.id
        guard !downloads.isDownloaded(item.id, episodeID: episodeID),
              !downloads.isDownloading(item.id, episodeID: episodeID) else { return }
        guard let session = await playSession(itemID: item.id, episodeID: episodeID) else { return }
        await downloads.download(
            item: item,
            episode: episode,
            session: session,
            serverURL: serverURL,
            token: token,
            coverURL: coverURL(itemID: item.id)
        )
    }

    func removeDownload(itemID: String, episodeID: String? = nil) {
        downloads.remove(itemID, episodeID: episodeID)
    }

    private func friendly(_ error: Error) -> String {
        if let apiError = error as? APIError { return apiError.message }
        return error.localizedDescription
    }
}
