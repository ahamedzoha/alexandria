import SwiftUI

/// A reusable edge-to-edge horizontal artwork shelf with a Title-2 / See-All
/// header, reusing the library grid's CoverCell at a fixed tile width.
struct HomeShelf: View {
    @Environment(AppState.self) private var app
    let title: String
    let symbol: String
    let items: [LibraryItem]
    var onSeeAll: (() -> Void)? = nil
    let onOpen: (LibraryItem) -> Void
    let onPlay: (LibraryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: title, symbol: symbol, onSeeAll: onSeeAll)
                .padding(.horizontal, Theme.Space.xl)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Space.m) {
                    ForEach(items) { item in
                        CoverCell(item: item,
                                  onOpen: { onOpen(item) },
                                  onPlay: { onPlay(item) })
                            .frame(width: 150)
                            .contextMenu { menu(for: item) }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .contentMargins(.horizontal, Theme.Space.xl, for: .scrollContent)
        }
    }

    // Mirrors LibraryGridView's per-item context menu so behavior is uniform.
    @ViewBuilder private func menu(for item: LibraryItem) -> some View {
        Button("Play", systemImage: "play.fill") { onPlay(item) }
        if app.downloads.isDownloaded(item.id) {
            Button("Remove Download", systemImage: "trash", role: .destructive) {
                app.removeDownload(itemID: item.id)
            }
        } else if app.downloads.activeDownloads[item.id] == nil {
            Button("Download for Offline", systemImage: "arrow.down.circle") {
                Task { await app.startDownload(item: item) }
            }
        }
        Divider()
        Button("Show Author", systemImage: "person") {
            app.showGroup(kind: .authors, value: item.author)
        }
        Button("Show Details", systemImage: "info.circle") { onOpen(item) }
    }
}

/// Section header: bold Title-2 label + optional "See All" chevron.
struct SectionHeader: View {
    let title: String
    let symbol: String
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol)
                .font(.title2.weight(.bold))
                .labelStyle(.titleAndIcon)
            Spacer()
            if let onSeeAll {
                Button(action: onSeeAll) {
                    HStack(spacing: 3) {
                        Text("See All")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(.tint)
                .help("Show all in Library")
            }
        }
    }
}
