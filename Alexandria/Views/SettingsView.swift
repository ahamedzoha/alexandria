import SwiftUI

/// The app's Settings window (⌘,).
struct SettingsView: View {
    @Environment(AppState.self) private var app

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
    }
}
