import SwiftUI

struct BrowseGroup: Identifiable {
    let id: String            // author / series / narrator name
    let count: Int
    let coverItemIDs: [String]
    var name: String { id }
}

/// Grid of author / series / narrator cards, each showing a fanned strip of
/// the group's covers plus a count badge. Tapping one filters the library grid.
struct GroupGridView: View {
    @Environment(AppState.self) private var app
    let kind: AppState.Browse

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 20)]

    private var groups: [BrowseGroup] {
        var buckets: [String: [String]] = [:]
        for item in app.items {
            let key: String?
            switch kind {
            case .authors: key = item.author
            case .narrators: key = item.narrator
            case .series: key = item.seriesBaseName
            default: key = nil
            }
            if let key, !key.isEmpty { buckets[key, default: []].append(item.id) }
        }
        return buckets
            .map { BrowseGroup(id: $0.key, count: $0.value.count, coverItemIDs: Array($0.value.prefix(4))) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: icon,
                                       description: Text("No entries found in this library."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(groups) { group in
                            GroupCard(group: group, icon: icon)
                                .contentShape(Rectangle())
                                .onTapGesture { app.showGroup(kind: kind, value: group.name) }
                        }
                    }
                    .padding(28)
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
        default: return "book"
        }
    }
}

struct GroupCard: View {
    @Environment(AppState.self) private var app
    let group: BrowseGroup
    let icon: String
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                fannedCovers
                countBadge
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(hovering ? 0.5 : 0.3), radius: hovering ? 12 : 6, y: hovering ? 7 : 3)
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }

            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
                Text(group.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
        }
    }

    private var fannedCovers: some View {
        GeometryReader { geo in
            let ids = group.coverItemIDs
            let n = max(1, min(ids.count, 4))
            HStack(spacing: 0) {
                ForEach(Array(ids.prefix(4).enumerated()), id: \.offset) { _, id in
                    RemoteImage(url: app.coverURL(itemID: id)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } fallback: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(width: geo.size.width / CGFloat(n), height: geo.size.height)
                    .clipped()
                }
            }
        }
    }

    private var countBadge: some View {
        Text("\(group.count)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.black.opacity(0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
            .padding(8)
    }
}
