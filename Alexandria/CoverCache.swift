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

    private nonisolated static func fetch(_ url: URL, token: String?) async -> NSImage? {
        // Local (downloaded) cover files are already on disk — just decode.
        if url.isFileURL {
            return NSImage(contentsOf: url)
        }

        let file = diskFile(for: url)
        if let file, let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            return image
        }

        var req = URLRequest(url: url)
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Retry a few times — self-hosted servers drop bursts of parallel requests.
        for attempt in 0..<3 {
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                if let image = NSImage(data: data) {
                    if let file { try? data.write(to: file) }
                    return image
                }
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
