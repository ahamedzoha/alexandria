import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    // NOTE: token in UserDefaults is fine for MVP. Move to Keychain before shipping.
    var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    var token: String? = UserDefaults.standard.string(forKey: "token")

    struct ItemProgress: Sendable {
        var fraction: Double
        var isFinished: Bool
    }

    var libraries: [Library] = []
    var selectedLibraryID: String?
    var items: [LibraryItem] = []
    var progressByItem: [String: ItemProgress] = [:]
    var isLoading = false
    var errorMessage: String?

    var isLoggedIn: Bool { !(token ?? "").isEmpty }

    private var api: APIClient { APIClient(serverURL: serverURL, token: token) }

    func login(server: String, username: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let cleaned = server.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let t = try await APIClient(serverURL: cleaned, token: nil)
                .login(username: username, password: password)
            serverURL = cleaned
            token = t
            UserDefaults.standard.set(cleaned, forKey: "serverURL")
            UserDefaults.standard.set(t, forKey: "token")
            await loadLibraries()
        } catch {
            errorMessage = friendly(error)
        }
    }

    func logout() {
        token = nil
        UserDefaults.standard.removeObject(forKey: "token")
        libraries = []
        items = []
        progressByItem = [:]
        selectedLibraryID = nil
        errorMessage = nil
    }

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

    func coverURL(itemID: String) -> URL? {
        api.coverURL(itemID: itemID)
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
        // Update the grid immediately, then persist (best-effort — never interrupt playback).
        let fraction = duration > 0 ? min(1, currentTime / duration) : 0
        progressByItem[itemID] = ItemProgress(fraction: fraction, isFinished: fraction >= 0.99)
        try? await api.updateProgress(itemID: itemID, currentTime: currentTime, duration: duration)
    }

    private func friendly(_ error: Error) -> String {
        if let apiError = error as? APIError { return apiError.message }
        return error.localizedDescription
    }
}
