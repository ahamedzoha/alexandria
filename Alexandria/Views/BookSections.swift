import SwiftUI

// Building blocks shared by the item detail sheet and the Now Playing
// inspector, so a book reads the same wherever it's shown.

/// Server/feed HTML flattened to readable plain text: line and paragraph
/// breaks survive, tags go, and the common entities decode.
func plainText(fromHTML html: String) -> String {
    var text = html
        .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        .replacingOccurrences(of: "(?i)</p\\s*>", with: "\n\n", options: .regularExpression)
        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    // &amp; last, so "&amp;lt;" decodes to the literal "&lt;" it encodes.
    for (entity, character) in [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                                ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
        text = text.replacingOccurrences(of: entity, with: character)
    }
    return text
        .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Secondary prose clamped to a few lines, with Read More / Read Less shown
/// only when the clamp actually hides something.
struct ExpandableText: View {
    let text: String
    var lineLimit = 4
    var font: Font = .callout

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            prose
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                .background(alignment: .topLeading) {
                    // Unclamped twin, measured to learn whether the clamp truncates.
                    Text(text)
                        .font(font)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            if expanded || fullHeight > shownHeight + 1 {
                Button(expanded ? "Read Less" : "Read More") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
                }
                .buttonStyle(.link)
                .font(font)
            }
        }
    }

    /// Selectable only once expanded: on macOS a selectable Text ignores its
    /// line limit when drawing, spilling the full text over whatever follows.
    @ViewBuilder private var prose: some View {
        let base = Text(text)
            .font(font)
            .foregroundStyle(.secondary)
        if expanded {
            base.textSelection(.enabled)
        } else {
            base.lineLimit(lineLimit)
        }
    }
}

/// Label/value metadata rows (Published, Publisher, Genres…). Rows whose
/// value is missing or empty are skipped.
struct MetadataRows: View {
    let rows: [(label: String, value: String?)]
    var labelWidth: CGFloat = 96

    private struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var visible: [Row] {
        rows.compactMap { row in
            guard let value = row.value, !value.isEmpty else { return nil }
            return Row(label: row.label, value: value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(visible) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .leading)
                    Text(row.value)
                        .font(.callout)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// One chapter line. Interactive (click to jump) only when `onSelect` is set,
/// i.e. when this book is the one loaded in the player.
struct ChapterRow: View {
    let number: Int
    let title: String
    let start: Double
    var isCurrent = false
    var isPlayed = false
    var accent: Color = .accentColor
    var onSelect: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        if let onSelect {
            Button(action: onSelect) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .help("Jump to \(title)")
                .accessibilityHint("Jumps to this chapter")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            Group {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(accent)
                } else {
                    Text("\(number)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, alignment: .leading)

            Text(title)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isPlayed ? HierarchicalShapeStyle.secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Format.timestamp(start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chapter \(number), \(title), starts at \(Format.timestamp(start))")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var rowFill: Color {
        if isCurrent { return Color.primary.opacity(0.07) }
        return hovering ? Color.primary.opacity(0.04) : .clear
    }
}

/// Storefront links for a book. Audible goes straight to the product when the
/// server has its ASIN; everything else is a search.
enum ExternalLinks {
    static func audible(asin: String?, title: String, author: String,
                        domain: String = AudibleStore.automatic.domain) -> URL? {
        if let asin, !asin.isEmpty {
            return URL(string: "https://www.\(domain)/pd/\(asin)")
        }
        return search("https://www.\(domain)/search", "keywords", "\(title) \(author)")
    }

    static func goodreads(isbn: String?, title: String, author: String) -> URL? {
        search("https://www.goodreads.com/search", "q", isbn.flatMap { $0.isEmpty ? nil : $0 } ?? "\(title) \(author)")
    }

    static func storyGraph(title: String, author: String) -> URL? {
        search("https://app.thestorygraph.com/browse", "search_term", "\(title) \(author)")
    }

    private static func search(_ base: String, _ key: String, _ query: String) -> URL? {
        var comps = URLComponents(string: base)
        comps?.queryItems = [URLQueryItem(name: key, value: query)]
        return comps?.url
    }
}
