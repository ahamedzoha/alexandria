import Foundation

/// The single in-flight launch: a new startPlayback cancels the previous one
/// so rapid clicks can't race their player.load calls (last click wins).
@MainActor private var startPlaybackTask: Task<Void, Never>?

/// Shared quick-play launcher: prefers a local download, else a server session,
/// then hands the session to the player. Used by the library grid, the search
/// dropdown, and the Home page so offline-first behavior stays identical.
/// Pass an episode to play a podcast episode; nil keeps the book behavior for
/// books and resolves podcasts to their resume-target episode (see
/// `AppState.resumeEpisode(for:)`), so every item-level entry point works for
/// podcasts unchanged. `startAt` begins at that position (a chapter picked
/// in the detail sheet) instead of the saved one. `onResult` fires on the
/// main actor: true once the player has loaded, false when nothing playable
/// was found (or the launch was superseded).
@MainActor
func startPlayback(item: LibraryItem, episode: PodcastEpisode? = nil, startAt: Double? = nil, app: AppState,
                   player: PlayerEngine, onResult: ((Bool) -> Void)? = nil) {
    startPlaybackTask?.cancel()
    startPlaybackTask = Task {
        var episode = episode
        if item.isPodcast, episode == nil {
            episode = await app.resumeEpisode(for: item)
            guard episode != nil else {
                onResult?(false)
                return
            }
        }
        guard !Task.isCancelled else { onResult?(false); return }
        let title = episode?.displayTitle ?? item.title
        let local = app.downloads.localSession(for: item.id, episodeID: episode?.id,
                                               serverProgress: app.progress(itemID: item.id, episodeID: episode?.id))
        var info: PlaybackInfo
        let cover: URL?
        if let local {
            info = local
            cover = app.downloads.localCoverURL(item.id)
        } else {
            do {
                info = try await app.playSession(itemID: item.id, episodeID: episode?.id)
            } catch {
                if !Task.isCancelled { app.presentFailure("Couldn't Play “\(title)”", error) }
                onResult?(false)
                return
            }
            cover = app.coverURL(itemID: item.id)
        }
        guard !Task.isCancelled else {
            onResult?(false)
            return
        }
        if let startAt {
            info = PlaybackInfo(id: info.id, episodeId: info.episodeId, audioTracks: info.audioTracks,
                                chapters: info.chapters, currentTime: startAt, duration: info.duration)
        }
        let loaded = player.load(session: info, itemID: item.id, episodeID: episode?.id,
                                 serverURL: app.serverURL, token: app.token,
                                 title: title,
                                 author: episode == nil ? item.author : item.title,
                                 cover: cover,
                                 sound: app.soundProfile(for: item))
        if loaded {
            // A download plays without a server session.
            app.sessionStarted(id: local == nil ? info.id : nil, itemID: item.id, episodeID: episode?.id)
            await app.playbackStarted(item: item, episode: episode)
        } else {
            app.presentFailure("Couldn't Play “\(title)”",
                               APIError(message: "The server didn't offer any audio this app can play."))
        }
        onResult?(loaded)
    }
}
