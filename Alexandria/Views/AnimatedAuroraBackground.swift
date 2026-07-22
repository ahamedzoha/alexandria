import SwiftUI

/// Slow-drifting blurred color blobs over a dark base — an animated "aurora"
/// backdrop for the splash / login screen.
struct AnimatedAuroraBackground: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let s = max(w, h)
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.04, blue: 0.10),
                                 Color(red: 0.10, green: 0.06, blue: 0.16)],
                        startPoint: .top, endPoint: .bottom
                    )
                    blob(.blue,   size: s * 0.95, x: w * 0.5 + cos(t * 0.15) * w * 0.28,      y: h * 0.32 + sin(t * 0.12) * h * 0.22)
                    blob(.purple, size: s * 0.85, x: w * 0.32 + cos(t * 0.20 + 1) * w * 0.30, y: h * 0.62 + sin(t * 0.17 + 2) * h * 0.24)
                    blob(.pink,   size: s * 0.72, x: w * 0.72 + sin(t * 0.18 + 3) * w * 0.26, y: h * 0.55 + cos(t * 0.14 + 1) * h * 0.22)
                    blob(.indigo, size: s * 0.80, x: w * 0.62 + cos(t * 0.10 + 2) * w * 0.30, y: h * 0.30 + sin(t * 0.20) * h * 0.20)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.55), color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: 70)
            .position(x: x, y: y)
    }
}
