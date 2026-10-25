import SwiftUI

// The two marks drawn on top of artwork, shared by every card so a cover
// reads the same on every shelf: one progress line, one play glyph.

/// Progress along a cover's bottom edge: a thin tinted line over a dark
/// track. Scaled rather than measured, so it never lays out at zero width
/// and grows back when a shelf is rebuilt.
struct CoverProgressEdge: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(.black.opacity(0.3))
            Rectangle()
                .fill(tint)
                .scaleEffect(x: min(1, max(0.03, fraction)), anchor: .leading)
        }
        .frame(height: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The quick-play glyph shown over a cover on hover or keyboard focus.
struct CoverPlayGlyph: View {
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.black.opacity(0.55), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}
