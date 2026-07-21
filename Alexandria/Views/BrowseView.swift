import SwiftUI

struct BrowseGroup: Identifiable {
    let id: String       // the author / series / narrator name
    let count: Int
    var name: String { id }
}

/// Lists distinct authors / series / narrators built from the loaded items.
/// Tapping one filters the library grid to that group.
struct GroupListView: View {
    @Environment(AppState.self) private var app
    let kind: AppState.Browse

    private var groups: [BrowseGroup] {
        var counts: [String: Int] = [:]
        for item in app.items {
            let key: String?
            switch kind {
            case .authors: key = item.author
            case .narrators: key = item.narrator
            case .series: key = item.seriesBaseName
            case .library: key = nil
            }
            if let key, !key.isEmpty { counts[key, default: 0] += 1 }
        }
        return counts
            .map { BrowseGroup(id: $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: icon,
                                       description: Text("No \(kind == .series ? "series" : "entries") found in this library."))
            } else {
                List(groups) { group in
                    Button {
                        app.showGroup(kind: kind, value: group.name)
                    } label: {
                        HStack {
                            Image(systemName: icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(group.name)
                            Spacer()
                            Text("\(group.count)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        switch kind {
        case .authors: return "person"
        case .narrators: return "mic"
        case .series: return "books.vertical"
        case .library: return "book"
        }
    }
}
