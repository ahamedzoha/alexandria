import SwiftUI

/// The app's Settings window (⌘,).
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var cacheBytes: Int64?
    @State private var libraryBytes: Int64?

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Picker("Scroll bars", selection: $app.scrollBarStyle) {
                    ForEach(ScrollBarStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Takes effect the next time you open Alexandria.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Books without their own setting", selection: $app.defaultSoundPreset) {
                    ForEach(SoundProfile.Preset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
            } header: {
                Text("Sound")
            } footer: {
                Text("Voice Boost makes quiet narration louder and clearer; Restore also removes tape hiss and room noise, which suits older recordings. Change it for any book from the Now Playing bar.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Buffer ahead while streaming", selection: $app.streamBufferMinutes) {
                    ForEach([10, 20, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("Keeps the next stretch of a streamed book in memory, so a dropped connection doesn't stop it. Nothing is saved to disk.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Downloads") {
                    HStack {
                        Text(sizeString(Double(app.downloads.totalSize)) ?? "None")
                            .monospacedDigit()
                        Button("Show Downloads") {
                            app.sidebar = .downloads
                            NSApp.keyWindow?.close()
                        }
                        .disabled(app.downloads.downloadedBooks.isEmpty)
                    }
                }
                LabeledContent("Covers and ratings") {
                    HStack {
                        Text(cacheBytes.map { sizeString(Double($0)) ?? "Empty" } ?? "…")
                            .monospacedDigit()
                        Button("Clear Cache") {
                            CoverCache.shared.clearAll()
                            Task { await measure() }
                        }
                    }
                }
                Picker("Keep covers up to", selection: $app.coverCacheLimitMB) {
                    ForEach([100, 250, 500], id: \.self) { Text("\($0) MB").tag($0) }
                }
                LabeledContent("Library for offline use") {
                    Text(libraryBytes.map { sizeString(Double($0)) ?? "None" } ?? "…")
                        .monospacedDigit()
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Covers are fetched again as you browse; the oldest unused go first once the limit is reached. The saved library is what lets Alexandria open offline.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show ratings from the web", isOn: $app.webRatingsEnabled)
                Picker("Audible store", selection: $app.audibleStore) {
                    ForEach(AudibleStore.allCases) { store in
                        Text(store.label).tag(store)
                    }
                }
                .disabled(!app.webRatingsEnabled)
            } header: {
                Text("Ratings")
            } footer: {
                Text("To find ratings, Alexandria sends a book's title and author, or its ASIN or ISBN, to Audible and Open Library. Results are kept on this Mac for a week.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task { await measure() }
        .onChange(of: app.coverCacheLimitMB) { Task { try? await Task.sleep(for: .seconds(1)); await measure() } }
    }

    private func measure() async {
        let store = app.snapshots
        let sizes = await Task.detached(priority: .utility) { (CoverCache.diskSize(), store.totalSize()) }.value
        cacheBytes = sizes.0
        libraryBytes = sizes.1
        await app.downloads.refreshSizes()
    }
}
