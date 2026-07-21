import SwiftUI

struct ItemDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                RemoteImage(url: app.coverURL(itemID: item.id)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } fallback: {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                        .overlay(Image(systemName: "headphones").foregroundStyle(.secondary))
                }
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.title2.bold())
                    Text(item.author).foregroundStyle(.secondary)
                    if let narrator = item.narrator {
                        Text("Narrated by \(narrator)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let duration = item.duration {
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            Button(action: startPlayback) {
                Label(loading ? "Loading…" : "Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(loading)

            downloadControl

            Spacer(minLength: 0)
        }
        .padding(24)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    @ViewBuilder private var downloadControl: some View {
        if app.downloads.isDownloaded(item.id) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                Text("Downloaded").foregroundStyle(.secondary)
                Spacer()
                Button("Remove", role: .destructive) { app.removeDownload(itemID: item.id) }
                    .buttonStyle(.borderless)
            }
            .font(.callout)
        } else if let progress = app.downloads.activeDownloads[item.id] {
            HStack(spacing: 8) {
                ProgressView(value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                Task { await app.startDownload(item: item) }
            } label: {
                Label("Download for offline", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func startPlayback() {
        loading = true
        Task {
            // Prefer local files when the book is downloaded (works offline).
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
