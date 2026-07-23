import SwiftUI

/// Modern glass dropdown of matching books, shown under the toolbar search
/// field on non-library pages (Authors / Series / Narrators / Stats).
/// Keyboard-driven: the parent tracks `highlighted`; ↑/↓ move it, ↵ opens.
struct SearchDropdown: View {
    @Environment(AppState.self) private var app

    /// Max rows the dropdown lists (and the parent lets ↑/↓ traverse).
    static let maxRows = 8

    let matches: [LibraryItem]
    let highlighted: Int
    var onSelect: (LibraryItem) -> Void
    var onPlay: (LibraryItem) -> Void
    var onShowAll: () -> Void

    private var shown: [LibraryItem] { Array(matches.prefix(Self.maxRows)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if matches.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(shown.indices, id: \.self) { index in
                                let item = shown[index]
                                SearchResultRow(
                                    item: item,
                                    isHighlighted: index == highlighted,
                                    onTap: { onSelect(item) },
                                    onPlay: { onPlay(item) }
                                )
                                .id(index)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: highlighted) { _, new in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(new, anchor: .center)
                        }
                    }
                }

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
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .themeShadow(Theme.Shadow.lifted)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption)
            Text(matches.isEmpty ? "No results" : "\(matches.count) result\(matches.count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
            Spacer()
            if !matches.isEmpty {
                Text("↑↓ navigate · ↵ play · esc clear")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
    let isHighlighted: Bool
    var onTap: () -> Void
    var onPlay: () -> Void
    @State private var hovering = false

    // Hover OR keyboard highlight surfaces the play affordance + row tint.
    private var active: Bool { hovering || isHighlighted }

    var body: some View {
        ZStack {
            // Base: the whole row is one button that opens the detail sheet.
            Button(action: onTap) {
                HStack(spacing: 12) {
                    cover
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
                        .fill(active ? Color.primary.opacity(0.09) : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // On top of (not inside) the row button, over the cover: a sibling
            // play button so a quick-play tap never also opens the sheet.
            if active {
                HStack {
                    Button(action: onPlay) { playButton }
                        .buttonStyle(.plain)
                        .help("Play")
                        .accessibilityLabel("Play \(item.title)")
                        .frame(width: 38)      // aligns over the 38pt cover
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)      // match the row's leading inset
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: active)
    }

    private var cover: some View {
        ZStack {
            RemoteImage(url: app.coverURL(itemID: item.id)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } fallback: {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "book.closed").font(.caption).foregroundStyle(.secondary))
            }
            // Dim the cover under the play button on hover/highlight.
            if active {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.black.opacity(0.28))
            }
        }
        .frame(width: 38, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // Compact cover-play affordance — the small-space cousin of the grid's.
    private var playButton: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(.black.opacity(0.5), in: Circle())
    }

    @ViewBuilder private var progressBadge: some View {
        let p = app.progress(itemID: item.id)
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
