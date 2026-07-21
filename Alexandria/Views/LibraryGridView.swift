import SwiftUI

struct LibraryGridView: View {
    @Environment(AppState.self) private var app
    @State private var selected: LibraryItem?

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 190), spacing: 22)]

    var body: some View {
        Group {
            if app.isLoading && app.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if app.visibleItems.isEmpty {
                ContentUnavailableView(
                    app.items.isEmpty ? "No items" : "No matches",
                    systemImage: app.items.isEmpty ? "book.closed" : "magnifyingglass",
                    description: Text(app.items.isEmpty
                        ? (app.errorMessage ?? "This library is empty.")
                        : "Try a different search or filter.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 26) {
                        ForEach(app.visibleItems) { item in
                            CoverCell(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = item }
                        }
                    }
                    .padding(28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selected) { item in
            ItemDetailView(item: item)
                .frame(minWidth: 440, minHeight: 320)
        }
    }
}

struct CoverCell: View {
    @Environment(AppState.self) private var app
    let item: LibraryItem
    @State private var hovering = false

    private var progress: AppState.ItemProgress? { app.progressByItem[item.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArt(url: app.coverURL(itemID: item.id), title: item.title)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottom) { progressBar }
                .overlay { finishedScrim }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) { finishedBadge }
                .overlay(alignment: .topLeading) { downloadBadge }
                .shadow(color: .black.opacity(hovering ? 0.5 : 0.3),
                        radius: hovering ? 12 : 6, y: hovering ? 7 : 3)
                .scaleEffect(hovering ? 1.03 : 1)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var progressBar: some View {
        if let progress, progress.fraction > 0.001, !progress.isFinished {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.5))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * progress.fraction))
                }
            }
            .frame(height: 5)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private var finishedScrim: some View {
        if progress?.isFinished == true {
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder private var finishedBadge: some View {
        if progress?.isFinished == true {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(Circle().fill(.green))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .padding(8)
                .shadow(radius: 3)
        }
    }

    @ViewBuilder private var downloadBadge: some View {
        if app.downloads.isDownloaded(item.id) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .blue)
                .padding(8)
                .shadow(radius: 3)
        }
    }
}

/// Cover image with a blurred backfill (so mixed aspect ratios sit in a uniform
/// square tile without cropping) and a colorful title fallback when there is no art.
struct CoverArt: View {
    let url: URL?
    let title: String

    var body: some View {
        RemoteImage(url: url) { image in
            ZStack {
                image.resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: 22).opacity(0.55)
                image.resizable().aspectRatio(contentMode: .fit)
            }
        } fallback: {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Image(systemName: "headphones")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.85))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 10)
            }
            .padding(8)
        }
    }

    // Stable per-title color (deterministic across launches).
    private var gradientColors: [Color] {
        let palette: [[Color]] = [
            [.indigo, .purple], [.blue, .teal], [.pink, .orange],
            [.teal, .green], [.orange, .red], [.purple, .pink],
            [.cyan, .blue], [.mint, .teal],
        ]
        let seed = title.utf8.reduce(0) { $0 &+ Int($1) }
        return palette[seed % palette.count]
    }
}
