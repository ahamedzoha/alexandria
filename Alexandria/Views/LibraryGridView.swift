import SwiftUI

struct LibraryGridView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @State private var selected: LibraryItem?

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 190), spacing: 22)]

    var body: some View {
        Group {
            if app.isLoading && app.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if app.items.isEmpty, let error = app.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't Load Library", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await app.loadLibraries() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if app.visibleItems.isEmpty {
                if app.items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing on this shelf yet", systemImage: "books.vertical")
                    } description: {
                        Text("When your server finishes scanning, your books land here — ready to play.")
                    } actions: {
                        Button("Refresh Library") { Task { await app.loadLibraries() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search or filter.")
                    )
                }
            } else if app.viewMode == .grid {
                gridView
            } else {
                tableView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selected) { item in
            ItemDetailView(item: item)
                .frame(width: 560, height: 680)
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 26) {
                ForEach(app.visibleItems) { item in
                    CoverCell(item: item,
                              onOpen: { selected = item },
                              onPlay: { playItem(item) })
                        .contextMenu { contextMenu(item) }
                }
            }
            .padding(28)
        }
    }

    private var tableView: some View {
        Table(app.visibleItems) {
            TableColumn("Title") { item in
                HStack(spacing: 8) {
                    RemoteImage(url: app.coverURL(itemID: item.id)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } fallback: {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(item.title).lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { selected = item }
                .contextMenu { contextMenu(item) }
            }
            TableColumn("Author") { item in Text(item.author).lineLimit(1) }
            TableColumn("Duration") { item in
                Text(durationString(item.duration) ?? "—").monospacedDigit().foregroundStyle(.secondary)
            }
            TableColumn("Progress") { item in progressCell(item) }
        }
    }

    @ViewBuilder private func progressCell(_ item: LibraryItem) -> some View {
        let p = app.progressByItem[item.id]
        if p?.isFinished == true {
            Label("Finished", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        } else if let p, p.fraction > 0.001 {
            Text("\(Int(p.fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private func contextMenu(_ item: LibraryItem) -> some View {
        Button("Play", systemImage: "play.fill") { playItem(item) }
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
        Button("Show Author", systemImage: "person") { app.showGroup(kind: .authors, value: item.author) }
        Button("Show Details", systemImage: "info.circle") { selected = item }
    }

    private func playItem(_ item: LibraryItem) {
        startPlayback(item: item, app: app, player: player)
    }
}

struct CoverCell: View {
    @Environment(AppState.self) private var app
    let item: LibraryItem
    let onOpen: () -> Void
    let onPlay: () -> Void
    @State private var hovering = false

    private var progress: AppState.ItemProgress? { app.progressByItem[item.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Button(action: onOpen) {
                    CoverArt(url: app.coverURL(itemID: item.id), title: item.title)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(alignment: .bottom) { progressBar }
                        .overlay { finishedScrim }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        }
                        .overlay(alignment: .topTrailing) { finishedBadge }
                        .overlay(alignment: .topLeading) { downloadBadge }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.title) by \(item.author)")

                if hovering {
                    RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous)
                        .fill(.black.opacity(0.38))
                        .allowsHitTesting(false)      // clicks pass through to the details button
                        .transition(.opacity)

                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(.black.opacity(0.55), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                            .shadow(radius: 6)
                    }
                    .buttonStyle(.plain)
                    .help("Play")
                    .accessibilityLabel("Play \(item.title)")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .hoverLift(cornerRadius: Theme.Radius.cover)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
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
