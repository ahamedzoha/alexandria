import SwiftUI
import AppKit

/// App-wide design tokens so spacing, radii, and surfaces stay consistent.
enum Theme {
    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 10
        static let cover: CGFloat = 10
        static let tile: CGFloat = 14
        static let pill: CGFloat = 999
    }
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 14
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
    }
    static let hairline = Color.white.opacity(0.08)

    /// Deterministic placeholder-art palette (stable across launches). Used for
    /// cover-art and avatar fallbacks — seed by a title or name.
    private static let placeholderPalette: [[Color]] = [
        [.indigo, .purple], [.blue, .teal], [.pink, .orange],
        [.teal, .green], [.orange, .red], [.purple, .pink],
        [.cyan, .blue], [.mint, .teal],
    ]

    static func placeholderColors(seed: String) -> [Color] {
        let n = seed.utf8.reduce(0) { $0 &+ Int($1) }
        return placeholderPalette[n % placeholderPalette.count]
    }
}

extension View {
    /// Navigation-layer surface (bars, floating controls). Liquid Glass on
    /// macOS 26+, a material fallback below. Per HIG, use this only for the
    /// navigation layer — never for content cards or list rows.
    func navGlass(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(NavGlassModifier(cornerRadius: cornerRadius))
    }

    /// Circular navigation-layer surface (e.g. a floating close button).
    @ViewBuilder func navGlassCircle() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .circle)
        } else {
            background(.ultraThinMaterial, in: Circle())
        }
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
        if #available(macOS 26, *) {
            content.glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.hairline))
        }
    }
}

extension View {
    /// Shared hover treatment for clickable cards: scale + shadow lift,
    /// pointing-hand cursor, and Reduce-Motion awareness.
    func hoverLift(cornerRadius: CGFloat = Theme.Radius.cover) -> some View {
        modifier(HoverLift())
    }
}

private struct HoverLift: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !reduceMotion ? 1.03 : 1)
            .shadow(color: .black.opacity(hovering ? 0.5 : 0.28),
                    radius: hovering ? 12 : 6, y: hovering ? 7 : 3)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}
