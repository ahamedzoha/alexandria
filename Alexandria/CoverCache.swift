import AppKit
import CryptoKit

/// Process-wide cache of cover images: memory (NSCache) -> disk (Caches/Covers)
/// -> network. Concurrent requests for the same URL share one in-flight fetch,
/// and downloads are written to disk so covers survive relaunches.
@MainActor
final class CoverCache {
    static let shared = CoverCache()

    /// Bearer token sent on network fetches when set. The app sets this on
    /// login/server switch alongside its APIClient, so cover URLs stay token-free.
    var authToken: String?

    private let memory: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 500
        return c
    }()

    /// In-flight fetches keyed by URL, so a burst of requests shares one task.
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    private init() {}

    // MARK: Lookup

    /// Memory-only lookup — synchronous, never touches disk or network.
    func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: Self.cacheKey(for: url) as NSString)
    }

    /// Full lookup: memory, then disk, then network (with retries).
    func image(for url: URL) async -> NSImage? {
        let key = Self.cacheKey(for: url) as NSString
        if let cached = memory.object(forKey: key) { return cached }

        if let existing = inFlight[url] {
            return await existing.value
        }
        let token = authToken
        let task = Task.detached { await Self.fetch(url, token: token) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: key) }
        return image
    }

    // MARK: Disk + network (runs off the main actor)

    /// A disk copy older than this is refetched (a cover changed on the
    /// server shows up within a week); if the refetch fails, the old copy is used.
    private nonisolated static let diskLifetime: TimeInterval = 7 * 86_400

    private nonisolated static func fetch(_ url: URL, token: String?) async -> NSImage? {
        // Local (downloaded) cover files are already on disk — just decode.
        if url.isFileURL {
            return NSImage(contentsOf: url)
        }

        let file = diskFile(for: url)
        var stale: NSImage?
        if let file, let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let written, Date().timeIntervalSince(written) < diskLifetime { return image }
            stale = image
        }

        var req = URLRequest(url: url)
        // An unreachable server fails fast instead of holding a cover for minutes.
        req.timeoutInterval = 15
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // At most a handful in flight: self-hosted servers drop bursts of
        // parallel requests (a full grid asks for hundreds at once).
        await FetchGate.shared.acquire()
        let fetched = await download(req, to: file)
        await FetchGate.shared.release()
        return fetched ?? stale
    }

    private nonisolated static func download(_ req: URLRequest, to file: URL?) async -> NSImage? {
        // Retry a couple of times — a dropped request is common under load.
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                if let image = NSImage(data: data) {
                    if let file { try? data.write(to: file, options: .atomic) }
                    return image
                }
            } catch let error as URLError where error.code == .timedOut || error.code == .cannotConnectToHost {
                return nil   // the server isn't there; retrying only delays the fallback
            } catch {
                // fall through and retry
            }
            try? await Task.sleep(nanoseconds: UInt64(200_000_000) * UInt64(attempt + 1))
        }
        return nil
    }

    /// Cache file for a URL — SHA256 of the normalized key keeps tokens and
    /// query params out of file names.
    private nonisolated static func diskFile(for url: URL) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(cacheKey(for: url).utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name, isDirectory: false)
    }

    /// Canonical cache key: the URL with any `token` query item stripped, so
    /// the same cover hits memory + disk no matter how the URL was built.
    private nonisolated static func cacheKey(for url: URL) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems, items.contains(where: { $0.name == "token" }) else {
            return url.absoluteString
        }
        let kept = items.filter { $0.name != "token" }
        comps.queryItems = kept.isEmpty ? nil : kept
        return comps.url?.absoluteString ?? url.absoluteString
    }
}

/// Limits concurrent cover downloads.
actor FetchGate {
    static let shared = FetchGate(limit: 6)

    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()   // the slot passes straight on
        }
    }
}
