import SwiftUI

/// Modern glass dropdown of matching books, shown under the toolbar search
/// field on non-library pages (Authors / Series / Narrators / Stats).
struct SearchDropdown: View {
    @Environment(AppState.self) private var app

    let matches: [LibraryItem]
    var onSelect: (LibraryItem) -> Void
    var onShowAll: () -> Void

    private let maxRows = 8

    private var shown: [LibraryItem] { Array(matches.prefix(maxRows)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if matches.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shown) { item in
                            SearchResultRow(item: item) { onSelect(item) }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)

                if matches.count > shown.count {
                    Divider().opacity(0.4)
                    showAllButton
                }
            }
        }
        .frame(width: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption)
            Text(matches.isEmpty ? "No results" : "\(matches.count) result\(matches.count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
            Spacer()
            Text(app.searchText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4))
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .foregroundStyle(.tertiary)
            Text("No books match “\(app.searchText)”")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var showAllButton: some View {
        Button(action: onShowAll) {
            HStack(spacing: 6) {
                Text("Show all \(matches.count) in Library")
                    .font(.callout.weight(.medium))
                Spacer()
                Image(systemName: "arrow.right")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SearchResultRow: View {
    @Environment(AppState.self) private var app
    let item: LibraryItem
    var onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RemoteImage(url: app.coverURL(itemID: item.id)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } fallback: {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.quaternary)
                        .overlay(Image(systemName: "book.closed").font(.caption).foregroundStyle(.secondary))
                }
                .frame(width: 38, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(item.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                progressBadge
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var progressBadge: some View {
        let p = app.progressByItem[item.id]
        if p?.isFinished == true {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else if let p, p.fraction > 0.001 {
            Text("\(Int(p.fraction * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
