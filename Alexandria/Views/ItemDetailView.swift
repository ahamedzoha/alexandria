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

    private func startPlayback() {
        loading = true
        Task {
            if let info = await app.playSession(itemID: item.id) {
                player.load(
                    session: info,
                    itemID: item.id,
                    serverURL: app.serverURL,
                    token: app.token,
                    title: item.title,
                    author: item.author,
                    cover: app.coverURL(itemID: item.id)
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
