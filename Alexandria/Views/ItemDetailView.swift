import SwiftUI

struct ItemDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    @State private var loading = false

    private var coverURL: URL? {
        app.downloads.localCoverURL(item.id) ?? app.coverURL(itemID: item.id)
    }

    private var progress: AppState.ItemProgress? { app.progressByItem[item.id] }

    var body: some View {
        ZStack {
            colorBleedBackground
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { closeButton }
    }

    // MARK: Background

    private var colorBleedBackground: some View {
        ZStack {
            Color.black
            RemoteImage(url: coverURL) { image in
                image.resizable().scaledToFill()
            } fallback: {
                LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .blur(radius: 60)
            .opacity(0.7)
            .saturation(1.4)

            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                RemoteImage(url: coverURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } fallback: {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(Image(systemName: "headphones").font(.largeTitle).foregroundStyle(.white.opacity(0.7)))
                }
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.6), radius: 22, y: 12)
                .padding(.top, 12)

                VStack(spacing: 6) {
                    Text(item.title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text(item.author)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.75))
                    if let narrator = item.narrator {
                        Text("Narrated by \(narrator)")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 12)

                metadataPills
                progressRow

                VStack(spacing: 10) {
                    playButton
                    downloadControl
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private var metadataPills: some View {
        HStack(spacing: 8) {
            if let duration = item.duration {
                pill(icon: "clock", text: formatDuration(duration))
            }
            if let series = item.seriesBaseName {
                pill(icon: "books.vertical", text: series)
            }
            if app.downloads.isDownloaded(item.id) {
                pill(icon: "arrow.down.circle.fill", text: "Offline")
            }
        }
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }

    @ViewBuilder private var progressRow: some View {
        if let progress, progress.fraction > 0.001 {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule()
                            .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * progress.fraction))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(progress.isFinished ? "Finished" : "\(Int(progress.fraction * 100))% complete")
                    Spacer()
                    if !progress.isFinished, let duration = item.duration {
                        Text("\(formatDuration(duration * (1 - progress.fraction))) left")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 8)
        }
    }

    private var playButton: some View {
        Button(action: startPlayback) {
            Label(playLabel, systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.75)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule()
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .opacity(loading ? 0.6 : 1)
    }

    private var playLabel: String {
        if loading { return "Loading…" }
        if let progress, progress.fraction > 0.001, !progress.isFinished { return "Resume" }
        return "Play"
    }

    @ViewBuilder private var downloadControl: some View {
        if app.downloads.isDownloaded(item.id) {
            Button(role: .destructive) {
                app.removeDownload(itemID: item.id)
            } label: {
                Label("Remove Download", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
        } else if let fraction = app.downloads.activeDownloads[item.id] {
            HStack(spacing: 8) {
                ProgressView(value: fraction).tint(.white)
                Text("\(Int(fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.vertical, 6)
        } else {
            Button {
                Task { await app.startDownload(item: item) }
            } label: {
                Label("Download for offline", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.callout.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(14)
    }

    private func startPlayback() {
        loading = true
        Task {
            let local = app.downloads.localSession(for: item.id)
            let info: PlaybackInfo?
            let cover: URL?
            if let local {
                info = local
                cover = app.downloads.localCoverURL(item.id)
            } else {
                info = await app.playSession(itemID: item.id)
                cover = app.coverURL(itemID: item.id)
            }

            if let info {
                player.load(
                    session: info,
                    itemID: item.id,
                    serverURL: app.serverURL,
                    token: app.token,
                    title: item.title,
                    author: item.author,
                    cover: cover
                )
                loading = false
                dismiss()
            } else {
                loading = false
            }
        }
    }
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}
