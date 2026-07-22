import SwiftUI

/// A restrained stat chip on the content-card surface: tinted icon, SF-Rounded
/// numeral that ticks with .numericText(), and a caption.
struct HomeStatTile: View {
    let symbol: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(tint.opacity(0.15)))
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.m)
        .contentCard(cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// The three-across listening snapshot below the greeting.
struct HomeStatRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            HomeStatTile(symbol: "headphones", tint: .blue,
                         value: hoursText, label: "Hours listened")
            HomeStatTile(symbol: "checkmark.circle.fill", tint: .green,
                         value: "\(app.finishedCount)", label: "Finished")
            HomeStatTile(symbol: "book.pages", tint: .orange,
                         value: "\(app.inProgressCount)", label: "In progress")
        }
        .animation(reduceMotion ? nil : .snappy, value: app.finishedCount)
        .animation(reduceMotion ? nil : .snappy, value: app.inProgressCount)
    }

    private var hoursText: String {
        let h = app.listenedHours
        return String(format: h < 10 ? "%.1f" : "%.0f", h)
    }
}
