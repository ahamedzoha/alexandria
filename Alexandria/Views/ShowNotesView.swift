import SwiftUI
import AppKit

/// Renders an episode's HTML show notes as native attributed text: system
/// fonts throughout (bold/italic preserved), clickable links, selectable.
struct ShowNotesView: View {
    let html: String

    @State private var notes: AttributedString?

    var body: some View {
        Group {
            if let notes {
                Text(notes)
                    .textSelection(.enabled)
            } else {
                // Tag-stripped fallback for the frame before the import lands
                // (or if the importer rejects the markup).
                Text(plainText)
                    .font(.callout)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: html) { notes = Self.render(html) }
    }

    private var plainText: String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Feed HTML is untrusted, and the `.html` importer fetches any resource a
    /// tag references during import. Strip every resource-bearing element
    /// before handing the markup over; prose survives, remote loads don't.
    private static func sanitized(_ html: String) -> String {
        // Paired elements whose bodies aren't prose (CSS, embeds, media
        // fallbacks) go entirely…
        let paired = "(?is)<(style|iframe|object|video|audio|picture)\\b[^>]*>.*?</\\1\\s*>"
        // …then any straggler tag — open, close, or self-closing.
        let single = "(?is)</?(img|picture|source|link|style|iframe|object|embed|video|audio)\\b[^>]*>"
        return html
            .replacingOccurrences(of: paired, with: "", options: .regularExpression)
            .replacingOccurrences(of: single, with: "", options: .regularExpression)
    }

    /// HTML -> AttributedString. The importer insists on Times New Roman, so
    /// every run is re-fonted with the system callout font, carrying over only
    /// bold/italic traits; link attributes survive and stay clickable.
    @MainActor private static func render(_ html: String) -> AttributedString? {
        let safe = sanitized(html)
        guard !safe.isEmpty, let data = safe.data(using: .utf8) else { return nil }
        guard let imported = try? NSMutableAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ) else { return nil }

        let full = NSRange(location: 0, length: imported.length)
        let base = NSFont.preferredFont(forTextStyle: .callout)
        imported.enumerateAttribute(.font, in: full) { value, range, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var symbolic: NSFontDescriptor.SymbolicTraits = []
            if traits.contains(.bold) { symbolic.insert(.bold) }
            if traits.contains(.italic) { symbolic.insert(.italic) }
            let descriptor = base.fontDescriptor.withSymbolicTraits(symbolic)
            imported.addAttribute(.font, value: NSFont(descriptor: descriptor, size: base.pointSize) ?? base,
                                  range: range)
        }
        // Drop imported text colors so the view's foreground style wins (the
        // detail sheet is dark); links keep their tint via the link attribute.
        imported.removeAttribute(.foregroundColor, range: full)

        // Only web/mail links stay clickable — anything else (file:, custom
        // schemes) is stripped down to plain text.
        imported.enumerateAttribute(.link, in: full) { value, range, _ in
            let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
            let scheme = url?.scheme?.lowercased() ?? ""
            if !["http", "https", "mailto"].contains(scheme) {
                imported.removeAttribute(.link, range: range)
            }
        }

        // The importer appends a trailing newline — trim it.
        while imported.string.hasSuffix("\n") {
            imported.deleteCharacters(in: NSRange(location: imported.length - 1, length: 1))
        }
        return AttributedString(imported)
    }
}
