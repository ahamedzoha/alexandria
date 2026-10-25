import Foundation
import AppKit
import AVFoundation
import MediaPlayer
import Observation

@MainActor
@Observable
final class PlayerEngine {
    struct Chapter: Identifiable, Sendable {
        let id: Int
        let start: Double
        let end: Double
        let title: String
    }

    private var player: AVQueuePlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservations: [NSKeyValueObservation] = []
    /// Live spectrum of the playing audio, for the toolbar visualizer.
    @ObservationIgnored let levelMeter = AudioLevelMeter()

    // Book layout: parallel arrays, one entry per audio track, in play order.
    private var trackOffsets: [Double] = []   // absolute start of each track within the book
    private var trackURLs: [URL] = []
    private var itemIndexMap: [ObjectIdentifier: Int] = [:]
    private var currentIndex = 0

    // Progress reporting
    private(set) var itemID = ""                // "" until something is loaded
    private(set) var currentEpisodeID: String?   // set when a podcast episode is playing
    private var authToken: String?          // sent as a Bearer header on track requests
    private var tickCount = 0
    private var didFireFinished = false
    /// Set by the app to persist position to the server. (itemID, episodeID, currentTime, duration)
    var onProgress: ((String, String?, Double, Double) -> Void)?
    /// Fired exactly once when playback reaches its natural end. (itemID, episodeID)
    var onFinished: ((String, String?) -> Void)?

    // Published state
    var chapters: [Chapter] = []
    var currentTitle = ""
    var currentAuthor = ""
    var coverURL: URL?
    var isPlaying = false
    var currentTime: Double = 0   // seconds into the whole book
    var duration: Double = 0      // whole-book duration
    var rate: Float = 1.0
    /// Set when the audio itself fails (a track 404s, the network drops, an
    /// unplayable file); MainView shows it once. Nil again after.
    var playbackError: String?

    // Sleep timer
    enum SleepTimer: Equatable {
        case off
        case seconds(Double)   // remaining seconds
        case endOfChapter
    }
    var sleepTimer: SleepTimer = .off
    /// Uptime of the last sleep-countdown tick; nil until the next tick after
    /// play, pause or a new timer.
    @ObservationIgnored private var lastSleepTick: TimeInterval?

    private var artwork: MPMediaItemArtwork?

    var currentChapterTitle: String {
        chapters.last(where: { currentTime + 0.5 >= $0.start })?.title ?? ""
    }

    /// Index into `chapters` of the chapter under the playhead.
    var currentChapterIndex: Int? {
        chapters.lastIndex(where: { currentTime + 0.5 >= $0.start })
    }

    private var currentChapterEnd: Double? {
        chapters.last(where: { currentTime + 0.5 >= $0.start })?.end
    }

    var sleepRemainingSeconds: Double? {
        if case .seconds(let s) = sleepTimer { return s }
        return nil
    }

    var isSleepArmed: Bool { sleepTimer != .off }

    init() {
        configureRemoteCommands()
    }

    // MARK: Loading

    @discardableResult
    func load(session: PlaybackInfo,
              itemID: String,
              episodeID: String? = nil,
              serverURL: String,
              token: String?,
              title: String,
              author: String,
              cover: URL?) -> Bool {
        // Resolve the new track list first — if nothing is playable, bail out
        // without tearing down whatever is currently playing.
        let sorted = session.audioTracks.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        var offsets: [Double] = []
        var urls: [URL] = []
        for track in sorted {
            guard let content = track.contentUrl,
                  let url = trackURL(content, serverURL: serverURL, token: token) else { continue }
            offsets.append(track.startOffset ?? (offsets.last ?? 0))
            urls.append(url)
        }
        guard !urls.isEmpty else { return false }

        reportNow()   // flush progress for whatever was playing before
        teardown()
        playbackError = nil
        self.itemID = itemID
        self.currentEpisodeID = episodeID ?? session.episodeId
        self.authToken = token
        tickCount = 0
        didFireFinished = false

        trackOffsets = offsets
        trackURLs = urls
        currentTitle = title
        currentAuthor = author
        coverURL = cover
        sleepTimer = .off

        let lastTrackDuration = sorted.last?.duration ?? 0
        duration = session.duration ?? ((offsets.last ?? 0) + lastTrackDuration)
        chapters = Self.chapters(from: session.chapters ?? [], duration: duration)
        currentTime = min(max(0, session.currentTime ?? 0), max(duration, 0))

        let startIndex = indexForTime(currentTime)
        buildQueue(fromIndex: startIndex)
        let within = currentTime - trackOffsets[currentIndex]
        if within > 0.5 { player?.seek(to: cmTime(within)) }
        loadArtwork(cover)
        play()
        return true
    }

    private func buildQueue(fromIndex idx: Int) {
        let start = min(max(idx, 0), trackURLs.count - 1)
        currentIndex = start

        // Before creating items: each new item registers a failure watcher,
        // which removeObservers() would otherwise cancel straight away.
        removeObservers()
        var items: [AVPlayerItem] = []
        itemIndexMap.removeAll()
        for i in start..<trackURLs.count {
            let item = playerItem(for: trackURLs[i])
            itemIndexMap[ObjectIdentifier(item)] = i
            items.append(item)
        }

        let queue = AVQueuePlayer(items: items)
        queue.automaticallyWaitsToMinimizeStalling = true
        player = queue
        addObservers()
    }

    // MARK: URL building

    /// Remote tracks authenticate with a Bearer header on the asset so the token
    /// stays out of URLs and logs. HLS segment requests inherit these options.
    private func playerItem(for url: URL) -> AVPlayerItem {
        let item: AVPlayerItem
        if !url.isFileURL, let authToken, !authToken.isEmpty {
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(authToken)"]
            ])
            item = AVPlayerItem(asset: asset)
        } else {
            item = AVPlayerItem(url: url)
        }
        levelMeter.attach(to: item)
        // A track that can't load used to mean silence and nothing else.
        statusObservations.append(item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let reason = item.error?.localizedDescription
            Task { @MainActor in self?.playbackFailed(reason) }
        })
        return item
    }

    private func playbackFailed(_ reason: String?) {
        guard !itemID.isEmpty, playbackError == nil else { return }
        player?.pause()
        isPlaying = false
        playbackError = reason ?? "The audio couldn't be played."
        updateNowPlayingInfo()
    }

    private func trackURL(_ content: String, serverURL: String, token: String?) -> URL? {
        var absolute = content
        if content.hasPrefix("/") {
            let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
            absolute = base + content
        }
        guard var comps = URLComponents(string: absolute) else { return nil }
        // Classify the path relative to the server base so a subpath reverse
        // proxy (https://host/abs -> /abs/hls/...) is detected correctly.
        var relativePath = comps.path
        if let basePath = URLComponents(string: serverURL.trimmingCharacters(in: .whitespaces))?.path {
            let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
            if !trimmedBase.isEmpty, relativePath.hasPrefix(trimmedBase) {
                relativePath = String(relativePath.dropFirst(trimmedBase.count))
            }
        }
        // HLS only: AVPlayer's segment requests don't reliably carry custom headers,
        // so transcode paths keep ?token=; everything else uses the Bearer header.
        if let token, !token.isEmpty, relativePath.hasPrefix("/hls/") {
            let hasToken = comps.queryItems?.contains { $0.name == "token" } ?? false
            if !hasToken {
                var q = comps.queryItems ?? []
                q.append(URLQueryItem(name: "token", value: token))
                comps.queryItems = q
            }
        }
        return comps.url
    }

    // MARK: Observers

    private func addObservers() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // Delivered on the main queue, so touching main-actor state is safe.
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                if let item = player.currentItem, let idx = self.itemIndexMap[ObjectIdentifier(item)] {
                    self.currentIndex = idx
                }
                let base = self.currentIndex < self.trackOffsets.count ? self.trackOffsets[self.currentIndex] : 0
                self.currentTime = base + time.seconds
                self.isPlaying = player.rate > 0

                if player.rate > 0 {
                    // Report to server roughly every 15s; refresh Now Playing every ~5s.
                    self.tickCount += 1
                    if self.tickCount % 10 == 0 { self.updateNowPlayingInfo() }
                    if self.tickCount >= 30 {
                        self.tickCount = 0
                        self.reportNow()
                    }
                    self.advanceSleepTimer()
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let item = note.object as? AVPlayerItem,
                   let idx = self.itemIndexMap[ObjectIdentifier(item)],
                   idx == self.trackURLs.count - 1 {
                    self.isPlaying = false   // reached the natural end
                    if !self.didFireFinished, !self.itemID.isEmpty, self.duration > 0 {
                        self.didFireFinished = true
                        self.currentTime = self.duration
                        self.reportNow()   // final position == duration so the server sees 100%
                        self.onFinished?(self.itemID, self.currentEpisodeID)
                    }
                }
            }
        }

        // Mid-play failures (the connection drops partway through a track).
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let item = note.object as? AVPlayerItem,
                      self.itemIndexMap[ObjectIdentifier(item)] != nil else { return }
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self.playbackFailed(error?.localizedDescription)
            }
        }
    }

    private func removeObservers() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        statusObservations.forEach { $0.invalidate() }
        statusObservations = []
    }

    private func teardown() {
        removeObservers()
        player?.pause()
        player = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Time helpers

    private func indexForTime(_ time: Double) -> Int {
        var idx = 0
        for (i, offset) in trackOffsets.enumerated() where offset <= time + 0.001 { idx = i }
        return idx
    }

    private func cmTime(_ seconds: Double) -> CMTime {
        CMTime(seconds: max(0, seconds), preferredTimescale: 600)
    }

    // MARK: Transport

    func play() {
        // Nothing loaded (Space on the login screen, a media key): claiming
        // to play would animate the menu bar icon over silence.
        guard player != nil else { return }
        // Play at the very end — after the book finished — starts it over.
        if duration > 0, currentTime >= duration - 1 { seek(to: 0) }
        guard let player else { return }
        player.rate = rate
        isPlaying = true
        lastSleepTick = nil
        updateNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        levelMeter.reset()
        lastSleepTick = nil
        reportNow()
        updateNowPlayingInfo()
    }

    /// Unload whatever is playing (logout, server switch): one last position
    /// report, then the empty state, so the Now Playing bars disappear and no
    /// later tick reports to a server the item doesn't belong to.
    func stop() {
        guard !itemID.isEmpty else { return }
        reportNow()
        teardown()
        itemID = ""
        currentEpisodeID = nil
        trackOffsets = []
        trackURLs = []
        itemIndexMap = [:]
        currentIndex = 0
        chapters = []
        currentTitle = ""
        currentAuthor = ""
        coverURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        sleepTimer = .off
    }

    /// Server chapters with every `end` filled in: a missing or zero end
    /// becomes the next chapter's start (the book's end for the last one) —
    /// otherwise "sleep at end of chapter" fired the moment it was set.
    nonisolated static func chapters(from raw: [PlaybackInfo.Chapter], duration: Double) -> [Chapter] {
        raw.enumerated().map { i, c in
            let start = c.start ?? 0
            let fallbackEnd = i + 1 < raw.count ? (raw[i + 1].start ?? duration) : duration
            let end = (c.end ?? 0) > start ? c.end! : fallbackEnd
            return Chapter(id: i, start: start, end: end, title: c.title ?? "Chapter \(i + 1)")
        }
    }

    private func reportNow() {
        guard !itemID.isEmpty, duration > 0 else { return }
        onProgress?(itemID, currentEpisodeID, currentTime, duration)
    }

    func toggle() { isPlaying ? pause() : play() }

    func seek(to seconds: Double) {
        guard !trackURLs.isEmpty else { return }
        let target = min(max(0, seconds), duration)
        let idx = indexForTime(target)
        let within = target - trackOffsets[idx]
        // Seeking back from the end makes a later finish count again.
        if target < duration - 1 { didFireFinished = false }

        // At the natural end the queue has already dropped its last item, so
        // an in-track seek has nothing to seek; rebuild from the target track.
        if idx == currentIndex, let player, player.currentItem != nil {
            player.seek(to: cmTime(within))
            currentTime = target
        } else {
            let wasPlaying = isPlaying
            buildQueue(fromIndex: idx)
            player?.seek(to: cmTime(within))
            currentTime = target
            if wasPlaying { play() }
        }
        reportNow()
        updateNowPlayingInfo()
    }

    func skip(_ delta: Double) { seek(to: currentTime + delta) }

    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying { player?.rate = newRate }
        updateNowPlayingInfo()
    }

    // MARK: Chapters

    func nextChapter() {
        guard let next = chapters.first(where: { $0.start > currentTime + 0.5 }) else { return }
        seek(to: next.start)
    }

    func prevChapter() {
        guard let current = chapters.last(where: { currentTime + 0.5 >= $0.start }) else {
            seek(to: 0); return
        }
        // If we're more than 3s into the chapter, restart it; otherwise jump to the previous one.
        if currentTime - current.start > 3 {
            seek(to: current.start)
        } else if let i = chapters.firstIndex(where: { $0.id == current.id }), i > 0 {
            seek(to: chapters[i - 1].start)
        } else {
            seek(to: 0)
        }
    }

    // MARK: Sleep timer

    func setSleepTimer(minutes: Int) {
        player?.volume = 1
        lastSleepTick = nil
        sleepTimer = .seconds(Double(minutes * 60))
    }

    func setSleepEndOfChapter() {
        player?.volume = 1
        lastSleepTick = nil
        sleepTimer = .endOfChapter
    }

    func cancelSleepTimer() {
        player?.volume = 1
        sleepTimer = .off
    }

    /// Called on every playback tick. Ticks follow the book's timeline —
    /// twice a second at 1×, four times at 2× — so the countdown runs on
    /// wall-clock time between ticks; counting ticks made a 30-minute timer
    /// stop after 15 at 2×. Gaps over a second (a stall) aren't counted.
    func advanceSleepTimer(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let elapsed = lastSleepTick.map { min(max(0, now - $0), 1) } ?? 0
        lastSleepTick = now
        switch sleepTimer {
        case .off:
            break
        case .seconds(let remaining):
            let r = remaining - elapsed
            if r <= 0 {
                triggerSleep()
            } else {
                sleepTimer = .seconds(r)
                if r <= 5 { player?.volume = Float(r / 5) }   // fade out over last 5s
            }
        case .endOfChapter:
            if let end = currentChapterEnd, currentTime >= end - 0.25 {
                triggerSleep()
            }
        }
    }

    private func triggerSleep() {
        sleepTimer = .off
        pause()
        player?.volume = 1
    }

    // MARK: Now Playing / remote commands

    private func configureRemoteCommands() {
        configureCommands(on: MPRemoteCommandCenter.shared())
    }

    private func configureCommands(on center: MPRemoteCommandCenter) {
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(30) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(-15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        let infoCenter = MPNowPlayingInfoCenter.default()
        guard !currentTitle.isEmpty else {
            infoCenter.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentChapterTitle.isEmpty ? currentTitle : currentChapterTitle,
            MPMediaItemPropertyAlbumTitle: currentTitle,
            MPMediaItemPropertyArtist: currentAuthor,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
    }

    private func loadArtwork(_ url: URL?) {
        artwork = nil
        guard let url else { return }
        Task { [weak self] in
            guard let image = await CoverCache.shared.image(for: url) else { return }
            // A newer load may have swapped the cover while we were fetching.
            guard let self, self.coverURL == url else { return }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.artwork = art
            self.updateNowPlayingInfo()
        }
    }
}
