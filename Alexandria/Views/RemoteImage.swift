import SwiftUI
import AppKit

/// Process-wide cache of decoded cover images.
enum CoverCache {
    static let shared: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 500
        return c
    }()
}

@MainActor
@Observable
final class ImageLoader {
    enum LoadState {
        case loading
        case loaded(NSImage)
        case failed
    }

    var state: LoadState = .loading
    private var loadedURL: URL?

    func load(_ url: URL?) async {
        guard let url else { state = .failed; return }
        // Already showing this URL's result.
        if loadedURL == url, case .loaded = state { return }

        let key = url.absoluteString as NSString
        if let cached = CoverCache.shared.object(forKey: key) {
            loadedURL = url
            state = .loaded(cached)
            return
        }

        state = .loading
        // Retry a few times — self-hosted servers drop bursts of parallel requests.
        for attempt in 0..<3 {
            if Task.isCancelled { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                if let image = NSImage(data: data) {
                    CoverCache.shared.setObject(image, forKey: key)
                    loadedURL = url
                    state = .loaded(image)
                    return
                }
            } catch {
                if Task.isCancelled { return }
            }
            try? await Task.sleep(nanoseconds: UInt64(200_000_000) * UInt64(attempt + 1))
        }
        state = .failed
    }
}

/// Drop-in replacement for AsyncImage that caches decoded images and retries
/// transient failures, so cover art doesn't randomly drop out under load.
struct RemoteImage<Success: View, Fallback: View>: View {
    let url: URL?
    @ViewBuilder var success: (Image) -> Success
    @ViewBuilder var fallback: () -> Fallback

    @State private var loader = ImageLoader()

    var body: some View {
        content
            .task(id: url) { await loader.load(url) }
    }

    @ViewBuilder private var content: some View {
        switch loader.state {
        case .loading:
            Rectangle().fill(.quaternary)
                .overlay(ProgressView().controlSize(.small))
        case .loaded(let nsImage):
            success(Image(nsImage: nsImage))
        case .failed:
            fallback()
        }
    }
}
