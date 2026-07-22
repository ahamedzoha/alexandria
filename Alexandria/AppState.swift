import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    struct ItemProgress: Sendable {
        var fraction: Double
        var isFinished: Bool
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

    // Sidebar sections / browse grouping
    enum Browse: Hashable, Sendable {
        case library
        case authors
        case series
        case narrators
        case stats
    }

    // Servers (tokens live in the Keychain, keyed by server id)
    var servers: [ServerRef] = []
    var activeServerID: String?

    // Library data
    var libraries: [Library] = []
    var selectedLibraryID: String?
    var items: [LibraryItem] = []
    var progressByItem: [String: ItemProgress] = [:]
    let downloads = DownloadStore()
    var isLoading = false
    var errorMessage: String?

    // Search / sort / filter / browse
    var searchText = ""
    var sort: LibrarySort = .title
    var filter: LibraryFilter = .all
    var sidebar: Browse = .library
    var groupKind: Browse?
    var groupValue: String?
    var stats: LibraryStats?
    var authors: [AuthorRef] = []

    init() {
        loadServers()
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
            case .library, .stats: break
            }
        }

        switch filter {
        case .all:
            break
        case .inProgress:
            result = result.filter {
                let p = progressByItem[$0.id]
                return (p?.fraction ?? 0) > 0.001 && !(p?.isFinished ?? false)
            }
        case .finished:
            result = result.filter { progressByItem[$0.id]?.isFinished ?? false }
        case .notStarted:
            result = result.filter { (progressByItem[$0.id]?.fraction ?? 0) <= 0.001 }
        case .downloaded:
            result = result.filter { downloads.isDownloaded($0.id) }
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
            result.sort { (progressByItem[$0.id]?.fraction ?? 0) > (progressByItem[$1.id]?.fraction ?? 0) }
        }

        return result
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
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            let displayName = trimmedName.isEmpty ? hostName(cleaned) : trimmedName
            UserDefaults.standard.set(t, forKey: tokenKey(id))
            servers.append(ServerRef(id: id, name: displayName, url: cleaned))
            activeServerID = id
            persistServers()
            resetLibraryState()
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
        resetLibraryState()
        await loadLibraries()
    }

    func removeServer(_ id: String) {
        UserDefaults.standard.removeObject(forKey: tokenKey(id))
        servers.removeAll { $0.id == id }
        if activeServerID == id { activeServerID = servers.first?.id }
        persistServers()
        resetLibraryState()
        if activeServerID != nil {
            Task { await loadLibraries() }
        }
    }

    func logout() {
        if let id = activeServerID { removeServer(id) }
    }

    private func resetLibraryState() {
        libraries = []
        items = []
        progressByItem = [:]
        selectedLibraryID = nil
        searchText = ""
        groupKind = nil
        groupValue = nil
        sidebar = .library
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
            if let id = selectedLibraryID { await loadItems(libraryID: id) }
        } catch {
            errorMessage = friendly(error)
        }
    }

    func loadProgress() async {
        guard let list = try? await api.mediaProgress() else { return }
        var map: [String: ItemProgress] = [:]
        for entry in list {
            guard let id = entry.libraryItemId else { continue }
            map[id] = ItemProgress(fraction: entry.progress ?? 0, isFinished: entry.isFinished ?? false)
        }
        progressByItem = map
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
        case .library, .stats: return nil
        }
    }

    // MARK: Playback support

    func coverURL(itemID: String) -> URL? {
        api.coverURL(itemID: itemID)
    }

    func itemDetail(itemID: String) async -> ItemDetail? {
        try? await api.itemDetail(itemID: itemID)
    }

    func loadStats() async {
        guard let id = selectedLibraryID ?? libraries.first?.id else { return }
        stats = try? await api.libraryStats(libraryID: id)
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

    func playSession(itemID: String) async -> PlaybackInfo? {
        do {
            return try await api.play(itemID: itemID)
        } catch {
            errorMessage = friendly(error)
            return nil
        }
    }

    func reportProgress(itemID: String, currentTime: Double, duration: Double) async {
        let fraction = duration > 0 ? min(1, currentTime / duration) : 0
        progressByItem[itemID] = ItemProgress(fraction: fraction, isFinished: fraction >= 0.99)
        downloads.saveProgress(itemID: itemID, currentTime: currentTime, duration: duration)

        do {
            try await api.updateProgress(itemID: itemID, currentTime: currentTime, duration: duration)
            await downloads.flushPending(api: api)
        } catch {
            downloads.queuePending(itemID: itemID, currentTime: currentTime, duration: duration)
        }
    }

    func flushPendingProgress() async {
        await downloads.flushPending(api: api)
    }

    // MARK: Downloads

    func startDownload(item: LibraryItem) async {
        guard !downloads.isDownloaded(item.id), !downloads.isDownloading(item.id) else { return }
        guard let session = await playSession(itemID: item.id) else { return }
        await downloads.download(
            item: item,
            session: session,
            serverURL: serverURL,
            token: token,
            coverURL: coverURL(itemID: item.id)
        )
    }

    func removeDownload(itemID: String) {
        downloads.remove(itemID)
    }

    private func friendly(_ error: Error) -> String {
        if let apiError = error as? APIError { return apiError.message }
        return error.localizedDescription
    }
}
