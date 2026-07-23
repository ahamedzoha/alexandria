import SwiftUI
import AppKit

/// App-wide design tokens so spacing, radii, and surfaces stay consistent.
enum Theme {
    enum Radius {
        static let card: CGFloat = 16
        static let cover: CGFloat = 10
        static let pill: CGFloat = 999
    }
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 14
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
    }
    /// Semantic hairline for card borders and row separators. Adapts to both
    /// appearances — never a white-opacity literal.
    static let hairline = Color(nsColor: .separatorColor)

    /// Semantic type ramp. Tokens match the dominant sizes already in use
    /// across the views, so adopting them is visually a no-op.
    enum Typography {
        /// Shelf/section headers on Home and Browse.
        static let shelfTitle: Font = .title2.weight(.bold)
        /// Titles on grid cards and episode cards.
        static let cardTitle: Font = .subheadline.weight(.semibold)
        /// Secondary metadata lines (author, duration, counts).
        static let meta: Font = .caption
        /// The Home hero heading.
        static let heroTitle: Font = .largeTitle.weight(.bold)
    }

    /// A subtle elevation recipe (HIG: low opacity, small y offset).
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    enum Shadow {
        /// Resting card elevation.
        static let card = ShadowStyle(color: .black.opacity(0.10), radius: 5, y: 2)
        /// Hovered / floating elevation.
        static let lifted = ShadowStyle(color: .black.opacity(0.16), radius: 10, y: 5)
    }

    /// Deterministic placeholder-art palette (stable across launches). Used for
    /// cover-art and avatar fallbacks — seed by a title or name. Duotones are
    /// system colors softened toward gray so they stay adaptive and read
    /// native in both appearances rather than stock-gradient loud.
    private static let placeholderPalette: [[Color]] = [
        [Color.blue.mix(with: .gray, by: 0.35), Color.teal.mix(with: .gray, by: 0.45)],
        [Color.teal.mix(with: .gray, by: 0.35), Color.green.mix(with: .gray, by: 0.45)],
        [Color.brown.mix(with: .gray, by: 0.30), Color.orange.mix(with: .gray, by: 0.50)],
        [Color.cyan.mix(with: .gray, by: 0.40), Color.blue.mix(with: .gray, by: 0.50)],
        [Color.orange.mix(with: .gray, by: 0.40), Color.red.mix(with: .gray, by: 0.50)],
        [Color.green.mix(with: .gray, by: 0.40), Color.mint.mix(with: .gray, by: 0.50)],
        [Color.red.mix(with: .gray, by: 0.45), Color.brown.mix(with: .gray, by: 0.40)],
        [Color.mint.mix(with: .gray, by: 0.45), Color.cyan.mix(with: .gray, by: 0.50)],
    ]

    static func placeholderColors(seed: String) -> [Color] {
        let n = seed.utf8.reduce(0) { $0 &+ Int($1) }
        return placeholderPalette[n % placeholderPalette.count]
    }
}

extension View {
    /// Navigation-layer surface (bars, floating controls). Liquid Glass.
    /// Per HIG, use this only for the navigation layer — never for content
    /// cards or list rows.
    func navGlass(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(NavGlassModifier(cornerRadius: cornerRadius))
    }

    /// Circular navigation-layer surface (e.g. a floating close button).
    func navGlassCircle() -> some View {
        glassEffect(.regular, in: .circle)
    }

    /// Content-layer card surface (stats cards, detail panels). Always a
    /// material — content never gets glass.
    func contentCard(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.hairline))
    }
}

private struct NavGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.glassEffect(in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Shared hover treatment for clickable cards: scale + shadow lift,
    /// pointing-hand cursor, and Reduce-Motion awareness.
    func hoverLift() -> some View {
        modifier(HoverLift())
    }

    /// Apply a `Theme.Shadow` elevation token.
    func themeShadow(_ style: Theme.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, y: style.y)
    }
}

private struct HoverLift: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let elevation = hovering ? Theme.Shadow.lifted : Theme.Shadow.card
        content
            .scaleEffect(hovering && !reduceMotion ? 1.03 : 1)
            .shadow(color: elevation.color, radius: elevation.radius, y: elevation.y)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}
