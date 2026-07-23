import SwiftUI

/// One quiet stat: a rounded numeral that ticks with .numericText() over a
/// caption label. No card chrome — the hairline row it lives in provides the
/// structure.
struct HomeStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// The listening snapshot below the greeting: a single hairline-separated row —
/// quieter and more native than floating stat cards.
struct HomeStatRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            HomeStatTile(value: hoursText, label: "Hours listened")
            separator
            HomeStatTile(value: "\(app.finishedCount)", label: "Finished")
            separator
            HomeStatTile(value: "\(app.inProgressCount)", label: "In progress")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .snappy, value: hoursText)
        .animation(reduceMotion ? nil : .snappy, value: app.finishedCount)
        .animation(reduceMotion ? nil : .snappy, value: app.inProgressCount)
    }

    private var separator: some View {
        Divider().frame(height: 28)
    }

    private var hoursText: String {
        let h = app.listenedHours
        return String(format: h < 10 ? "%.1f" : "%.0f", h)
    }
}
