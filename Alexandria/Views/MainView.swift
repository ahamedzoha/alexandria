import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        return NavigationSplitView {
            List(selection: Binding(
                get: { app.selectedLibraryID },
                set: { id in if let id { Task { await app.selectLibrary(id) } } }
            )) {
                Section("Libraries") {
                    ForEach(app.libraries) { library in
                        Label(library.name, systemImage: icon(for: library))
                            .tag(library.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 320)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Log out", role: .destructive) { app.logout() }
                        .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(10)
            }
        } detail: {
            VStack(spacing: 0) {
                LibraryGridView()
                NowPlayingBar()
            }
            .navigationTitle(currentLibraryName)
            .searchable(text: $app.searchText, placement: .toolbar, prompt: "Search books")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort by", selection: $app.sort) {
                            ForEach(AppState.LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Divider()
                        Picker("Show", selection: $app.filter) {
                            ForEach(AppState.LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .help("Sort and filter")
                }
            }
        }
    }

    private var currentLibraryName: String {
        app.libraries.first { $0.id == app.selectedLibraryID }?.name ?? "Alexandria"
    }

    private func icon(for library: Library) -> String {
        library.mediaType == "podcast" ? "antenna.radiowaves.left.and.right" : "books.vertical"
    }
}
