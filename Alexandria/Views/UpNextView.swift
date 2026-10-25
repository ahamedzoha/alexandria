import SwiftUI

/// The Up Next side of the Now Playing inspector: what's playing, what the
/// user queued, and what follows automatically from the show or series.
///
/// - Select rows (⌘/⇧-click for several); Delete removes them, Return or a
///   double-click plays, right-click acts on the whole selection.
/// - Drag to reorder within either section.
/// - Drop books or episodes from anywhere in the app to add them to Playing
///   Next.
/// - Clear each section from its header, or everything from the menu.
struct UpNextView: View {
    @Environment(AppState.self) private var app
    @Environment(PlayerEngine.self) private var player
    @State private var selection: Set<QueueEntry.ID> = []
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var app = app
        let queue = app.queue
        VStack(spacing: 0) {
            Group {
                if queue.isEmpty && player.itemID.isEmpty {
                    ContentUnavailableView("Nothing Up Next", systemImage: "list.bullet",
                                           description: Text("Choose Play Next or Play Later on any episode or book, or drag one here."))
                        .frame(maxHeight: .infinity)
                } else {
                    list(queue)
                }
            }
            .overlay {
                // Drop feedback: the whole list outlines in the accent.
                RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .opacity(dropTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .dropDestination(for: QueueEntry.self) { entries, _ in
                entries.forEach(queue.playLater)
                return !entries.isEmpty
            } isTargeted: { dropTargeted = $0 }

            Divider()
            Toggle("Continue Playing Up Next", isOn: $app.autoPlayNextEpisodes)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.callout)
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s + 2)
                .help("When something finishes, play the next item in Up Next")
        }
    }

    private func list(_ queue: PlaybackQueue) -> some View {
        List(selection: $selection) {
            if !player.itemID.isEmpty {
                Section("Now Playing") {
                    QueueRow(title: player.currentTitle, subtitle: player.currentAuthor,
                             coverURL: player.coverURL, duration: nil, playing: player.isPlaying)
                        .selectionDisabled()
                }
            }
            if !queue.manual.isEmpty {
                Section {
                    ForEach(queue.manual) { entry in row(entry) }
                        .onMove { queue.moveManual(fromOffsets: $0, toOffset: $1) }
                } header: {
                    sectionHeader("Playing Next") { queue.clearManual() }
                }
            }
            if !queue.automatic.isEmpty {
                Section {
                    ForEach(queue.automatic) { entry in row(entry) }
                        .onMove { queue.moveAutomatic(fromOffsets: $0, toOffset: $1) }
                } header: {
                    sectionHeader(queue.automaticSource.map { "Up Next from \($0)" } ?? "Up Next") {
                        queue.clearAutomatic()
                    }
                }
            }
            if queue.isEmpty {
                Section {
                    Text("Choose Play Next or Play Later on any episode or book, or drag one here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            }
        }
        .listStyle(.inset)
        .onDeleteCommand { removeSelection() }
        .contextMenu(forSelectionType: QueueEntry.ID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            // Double-click or Return.
            if let entry = entries(ids).first { playNow(entry) }
        }
    }

    private func row(_ entry: QueueEntry) -> some View {
        QueueRow(title: entry.title, subtitle: entry.subtitle,
                 coverURL: app.coverURL(itemID: entry.item.id), duration: entry.duration, playing: false)
            .tag(entry.id)
    }

    private func sectionHeader(_ title: String, clear: @escaping () -> Void) -> some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer()
            Button("Clear", action: clear)
                .buttonStyle(.link)
                .font(.caption)
                .help("Remove everything in this section")
        }
    }

    @ViewBuilder private func menu(for ids: Set<QueueEntry.ID>) -> some View {
        let picked = entries(ids)
        if picked.isEmpty {
            Button("Clear Up Next", systemImage: "xmark.circle", role: .destructive) { app.queue.clearAll() }
                .disabled(app.queue.isEmpty)
        } else {
            if picked.count == 1, let entry = picked.first {
                Button("Play Now", systemImage: "play.fill") { playNow(entry) }
            }
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                app.queue.insert(picked, at: 0)
            }
            Button("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") {
                app.queue.insert(picked, at: app.queue.manual.count)
            }
            Divider()
            Button(picked.count == 1 ? "Remove from Up Next" : "Remove \(picked.count) Items",
                   systemImage: "minus.circle", role: .destructive) {
                app.queue.remove(Set(picked.map(\.id)))
                selection.subtract(ids)
            }
        }
    }

    /// The selected entries in queue order.
    private func entries(_ ids: Set<QueueEntry.ID>) -> [QueueEntry] {
        app.queue.upNext.filter { ids.contains($0.id) }
    }

    private func removeSelection() {
        app.queue.remove(selection)
        selection = []
    }

    private func playNow(_ entry: QueueEntry) {
        app.queue.remove(entry.id)
        selection.remove(entry.id)
        startPlayback(item: entry.item, episode: entry.episode, app: app, player: player)
    }
}

/// Cover, title, subtitle, duration — one line of the queue.
private struct QueueRow: View {
    let title: String
    let subtitle: String
    let coverURL: URL?
    let duration: Double?
    let playing: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s + 2) {
            RemoteImage(url: coverURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } fallback: {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(.quaternary)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if playing {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Playing")
            } else if let duration, let text = durationString(duration) {
                Text(text)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Lets a book or episode be dragged onto Up Next (or the ☰ button).
    /// Podcast shows aren't queueable, so they stay undraggable.
    @ViewBuilder func queueDraggable(_ item: LibraryItem?, episode: PodcastEpisode? = nil) -> some View {
        if let item, let entry = QueueEntry(item: item, episode: episode) {
            draggable(entry) {
                Label(entry.title, systemImage: entry.episode == nil ? "book" : "waveform")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
        } else {
            self
        }
    }
}
