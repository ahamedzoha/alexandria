import SwiftUI
import AppKit

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

        if let cached = CoverCache.shared.cachedImage(for: url) {
            loadedURL = url
            state = .loaded(cached)
            return
        }

        // Local (downloaded) cover files.
        if url.isFileURL {
            let image = await CoverCache.shared.image(for: url)
            if Task.isCancelled { return }
            if let image {
                loadedURL = url
                state = .loaded(image)
            } else {
                state = .failed
            }
            return
        }

        state = .loading
        let image = await CoverCache.shared.image(for: url)
        if Task.isCancelled { return }
        if let image {
            loadedURL = url
            withAnimation(.easeOut(duration: 0.25)) { state = .loaded(image) }
        } else {
            state = .failed
        }
    }
}

/// Drop-in replacement for AsyncImage that caches decoded images (memory + disk)
/// and retries transient failures, so cover art doesn't randomly drop out under load.
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
                .transition(.opacity)
        case .failed:
            fallback()
        }
    }
}
