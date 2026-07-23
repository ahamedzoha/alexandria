import SwiftUI
import Charts

// MARK: - Listening data

/// One bar of the hero chart: a book the user has actually listened to.
/// Hours = progress fraction × duration — the only per-item listening data the
/// server model exposes, so it is the only thing we chart (no fake sessions).
struct ListeningEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let author: String
    let hours: Double
    let fraction: Double   // completion 0...1
    let coverURL: URL?
}

/// "42 min" under an hour, "3.4 hr" under ten, "26 hr" beyond.
func listeningHoursLabel(_ hours: Double) -> String {
    if hours < 1 { return "\(Int((hours * 60).rounded())) min" }
    return String(format: hours < 10 ? "%.1f hr" : "%.0f hr", hours)
}

// MARK: - Single-hue intensity ramp

/// A saturation ramp of ONE hue family, seeded by the most-listened artwork's
/// accent (system accent as the fallback). Intensity 0...1 maps to saturation
/// and depth, so the chart's color IS the data — never a decorative rainbow.
struct IntensityRamp: Equatable {
    private let hue: Double
    private let saturation: Double
    private let brightness: Double

    init(base: Color) {
        let resolved = NSColor(base).usingColorSpace(.sRGB) ?? .controlAccentColor
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h)
        saturation = max(0.4, Double(s))
        brightness = max(0.5, Double(b))
    }

    /// Light mode ramps light→deep; dark mode ramps dim→bright. Both stay in
    /// the seed hue so the two appearances read as the same chart.
    func color(_ intensity: Double, dark: Bool) -> Color {
        let t = min(1, max(0, intensity))
        let sat = saturation * (0.45 + 0.55 * t)
        let bri = dark
            ? min(1, brightness * (0.78 + 0.32 * t))
            : min(1, brightness * (1.1 - 0.22 * t))
        return Color(hue: hue, saturation: sat, brightness: bri)
    }
}

// MARK: - Hero chart

/// Full-bleed listening bars: grow-in springs staggered ≤0.4s on first appear
/// (crossfade under Reduce Motion), hover shares `selection` with the rank
/// rows beneath, and palette shifts animate smoothly.
struct ListeningBarChart: View {
    let entries: [ListeningEntry]
    let ramp: IntensityRamp
    @Binding var selection: String?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown: [String: Double] = [:]
    @State private var revealed = false

    private var maxHours: Double { max(entries.map(\.hours).max() ?? 1, 0.001) }

    var body: some View {
        Chart(entries) { entry in
            BarMark(
                x: .value("Book", entry.id),
                y: .value("Hours", grown[entry.id] ?? 0),
                width: .ratio(0.68)
            )
            .cornerRadius(4)
            .foregroundStyle(ramp.color(entry.hours / maxHours, dark: scheme == .dark))
            .opacity(selection == nil || selection == entry.id ? 1 : 0.35)
            .accessibilityLabel(entry.title)
            .accessibilityValue("\(listeningHoursLabel(entry.hours)) listened")
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: entries.map(\.id))
        .chartYScale(domain: 0...(maxHours * 1.08))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(maxHours < 5 ? String(format: "%.1f h", v) : "\(Int(v)) h")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let anchor = proxy.plotFrame else { return }
                            let plot = geo[anchor]
                            guard plot.contains(location) else {
                                selection = nil
                                return
                            }
                            selection = proxy.value(atX: location.x - plot.minX, as: String.self)
                        case .ended:
                            selection = nil
                        }
                    }
            }
        }
        .opacity(revealed ? 1 : 0)
        .animation(.smooth(duration: 0.35), value: revealed)
        .animation(.smooth(duration: 0.2), value: selection)
        .animation(.smooth(duration: 0.5), value: ramp)
        .onAppear { grow(initial: true) }
        .onChange(of: entries) { grow(initial: false) }
    }

    private func grow(initial: Bool) {
        revealed = true
        if reduceMotion {
            // Bars land at rest; the reveal above is the crossfade.
            for entry in entries { grown[entry.id] = entry.hours }
        } else if initial {
            let step = entries.count > 1 ? 0.35 / Double(entries.count - 1) : 0
            for (index, entry) in entries.enumerated() {
                withAnimation(.spring(duration: 0.5, bounce: 0.15).delay(Double(index) * step)) {
                    grown[entry.id] = entry.hours
                }
            }
        } else {
            withAnimation(.smooth(duration: 0.4)) {
                for entry in entries { grown[entry.id] = entry.hours }
            }
        }
    }
}

// MARK: - Linked rank row

/// Compact stat row under the hero chart. Hovering it highlights the matching
/// bar (and vice versa) via the shared selection; clicking opens the book.
struct ListenRankRow: View {
    let rank: Int
    let entry: ListeningEntry
    let color: Color
    let highlighted: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, alignment: .trailing)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.callout.weight(highlighted ? .semibold : .regular))
                        .lineLimit(1)
                    Text(entry.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(color).frame(width: max(3, 56 * entry.fraction))
                }
                .frame(width: 56, height: 4)
                Text("\(Int(entry.fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                Text(listeningHoursLabel(entry.hours))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(highlighted ? Color.primary.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .accessibilityLabel("\(entry.title) by \(entry.author)")
        .accessibilityValue("\(listeningHoursLabel(entry.hours)) listened, \(Int(entry.fraction * 100)) percent complete")
    }
}

// MARK: - Proportion row (genres / authors)

/// Hairline-density row: label, count, and a thin proportional bar in the
/// shared hue ramp. The bar grows in with a staggered spring (crossfades under
/// Reduce Motion). Rows with an action get hover affordances.
struct ProportionRow: View {
    let label: String
    let value: Int
    let fraction: Double   // vs. the section max
    let color: Color
    let delay: Double
    var action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var hovering = false

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
                    .onHover { hovering = $0 }
            } else {
                content
            }
        }
        .onAppear {
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.spring(duration: 0.5, bounce: 0.15).delay(delay)) { grown = true }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private var content: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.callout.weight(hovering ? .semibold : .regular))
                    .lineLimit(1)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .opacity(hovering ? 1 : 0)
                }
                Spacer(minLength: 8)
                Text("\(value)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(color)
                        .frame(width: grown ? max(3, geo.size.width * fraction) : 0)
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .background(hovering ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
