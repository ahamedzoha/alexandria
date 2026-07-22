import Foundation

/// Shared quick-play launcher: prefers a local download, else a server session,
/// then hands the session to the player. Used by the library grid, the search
/// dropdown, and the Home page so offline-first behavior stays identical.
@MainActor
func startPlayback(item: LibraryItem, app: AppState, player: PlayerEngine) {
    Task {
        let local = app.downloads.localSession(for: item.id)
        let info: PlaybackInfo?
        let cover: URL?
        if let local {
            info = local
            cover = app.downloads.localCoverURL(item.id)
        } else {
            info = await app.playSession(itemID: item.id)
            cover = app.coverURL(itemID: item.id)
        }
        if let info {
            player.load(session: info, itemID: item.id, serverURL: app.serverURL,
                        token: app.token, title: item.title, author: item.author, cover: cover)
        }
    }
}
