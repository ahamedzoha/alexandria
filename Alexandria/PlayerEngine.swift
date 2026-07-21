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

    // Book layout: parallel arrays, one entry per audio track, in play order.
    private var trackOffsets: [Double] = []   // absolute start of each track within the book
    private var trackURLs: [URL] = []
    private var itemIndexMap: [ObjectIdentifier: Int] = [:]
    private var currentIndex = 0

    // Progress reporting
    private var itemID = ""
    private var tickCount = 0
    /// Set by the app to persist position to the server. (itemID, currentTime, duration)
    var onProgress: ((String, Double, Double) -> Void)?

    // Published state
    var chapters: [Chapter] = []
    var currentTitle = ""
    var currentAuthor = ""
    var coverURL: URL?
    var isPlaying = false
    var currentTime: Double = 0   // seconds into the whole book
    var duration: Double = 0      // whole-book duration
    var rate: Float = 1.0

    // Sleep timer
    enum SleepTimer: Equatable {
        case off
        case seconds(Double)   // remaining seconds
        case endOfChapter
    }
    var sleepTimer: SleepTimer = .off

    private var artwork: MPMediaItemArtwork?

    var currentChapterTitle: String {
        chapters.last(where: { currentTime + 0.5 >= $0.start })?.title ?? ""
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

    func load(session: PlaybackInfo,
              itemID: String,
              serverURL: String,
              token: String?,
              title: String,
              author: String,
              cover: URL?) {
        reportNow()   // flush progress for whatever was playing before
        teardown()
        self.itemID = itemID
        tickCount = 0

        let sorted = session.audioTracks.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        var offsets: [Double] = []
        var urls: [URL] = []
        for track in sorted {
            guard let content = track.contentUrl,
                  let url = trackURL(content, serverURL: serverURL, token: token) else { continue }
            offsets.append(track.startOffset ?? (offsets.last ?? 0))
            urls.append(url)
        }
        guard !urls.isEmpty else { return }

        trackOffsets = offsets
        trackURLs = urls
        chapters = (session.chapters ?? []).enumerated().map { i, c in
            Chapter(id: i, start: c.start ?? 0, end: c.end ?? 0, title: c.title ?? "Chapter \(i + 1)")
        }

        currentTitle = title
        currentAuthor = author
        coverURL = cover
        sleepTimer = .off

        let lastTrackDuration = sorted.last?.duration ?? 0
        duration = session.duration ?? ((offsets.last ?? 0) + lastTrackDuration)
        currentTime = min(max(0, session.currentTime ?? 0), max(duration, 0))

        let startIndex = indexForTime(currentTime)
        buildQueue(fromIndex: startIndex)
        let within = currentTime - trackOffsets[currentIndex]
        if within > 0.5 { player?.seek(to: cmTime(within)) }
        loadArtwork(cover)
        play()
    }

    private func buildQueue(fromIndex idx: Int) {
        let start = min(max(idx, 0), trackURLs.count - 1)
        currentIndex = start

        var items: [AVPlayerItem] = []
        itemIndexMap.removeAll()
        for i in start..<trackURLs.count {
            let item = AVPlayerItem(url: trackURLs[i])
            itemIndexMap[ObjectIdentifier(item)] = i
            items.append(item)
        }

        removeObservers()
        let queue = AVQueuePlayer(items: items)
        queue.automaticallyWaitsToMinimizeStalling = true
        player = queue
        addObservers()
    }

    // MARK: URL building

    private func trackURL(_ content: String, serverURL: String, token: String?) -> URL? {
        var absolute = content
        if content.hasPrefix("/") {
            let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
            absolute = base + content
        }
        guard var comps = URLComponents(string: absolute) else { return nil }
        if let token, !token.isEmpty {
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
                    self.advanceSleepTimer(step: 0.5)
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
                    self.isPlaying = false   // reached the end of the book
                }
            }
        }
    }

    private func removeObservers() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func teardown() {
        removeObservers()
        player?.pause()
        player = nil
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
        player?.rate = rate
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        reportNow()
        updateNowPlayingInfo()
    }

    private func reportNow() {
        guard !itemID.isEmpty, duration > 0 else { return }
        onProgress?(itemID, currentTime, duration)
    }

    func toggle() { isPlaying ? pause() : play() }

    func seek(to seconds: Double) {
        guard !trackURLs.isEmpty else { return }
        let target = min(max(0, seconds), duration)
        let idx = indexForTime(target)
        let within = target - trackOffsets[idx]

        if idx == currentIndex, let player {
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
        sleepTimer = .seconds(Double(minutes * 60))
    }

    func setSleepEndOfChapter() {
        player?.volume = 1
        sleepTimer = .endOfChapter
    }

    func cancelSleepTimer() {
        player?.volume = 1
        sleepTimer = .off
    }

    private func advanceSleepTimer(step: Double) {
        switch sleepTimer {
        case .off:
            break
        case .seconds(let remaining):
            let r = remaining - step
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
        let center = MPRemoteCommandCenter.shared()

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
        guard !currentTitle.isEmpty else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func loadArtwork(_ url: URL?) {
        artwork = nil
        guard let url else { return }
        Task { [weak self] in
            guard let image = await Self.fetchImage(url) else { return }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self?.artwork = art
            self?.updateNowPlayingInfo()
        }
    }

    private static func fetchImage(_ url: URL) async -> NSImage? {
        let key = url.absoluteString as NSString
        if let cached = CoverCache.shared.object(forKey: key) { return cached }
        if url.isFileURL {
            guard let image = NSImage(contentsOf: url) else { return nil }
            CoverCache.shared.setObject(image, forKey: key)
            return image
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else { return nil }
        CoverCache.shared.setObject(image, forKey: key)
        return image
    }
}
