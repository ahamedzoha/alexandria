import SwiftUI

/// Home's opening moment: a time-of-day greeting, today's listening folded
/// into the date line, the last seven days as a small bar chart with a live
/// readout and streak, and the library-completion ring. Bold through type
/// scale, real numbers and one authored entrance (bars grow, numerals roll),
/// not through decoration — the page stays on the plain window background.
struct ListeningHeader: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The entrance (bars growing from zero, totals rolling up) plays once per
    /// launch, like HomeView's own cascade; Home is rebuilt on every return and
    /// a chart that re-grew each time read as a glitch, not a flourish.
    @MainActor private static var hasEntered = false
    @State private var entered = ListeningHeader.hasEntered
    /// Week total the readout currently shows — lags the real total only
    /// during the first roll-up, otherwise tracks it (animated).
    @State private var shownWeekSeconds: Double = 0
    /// The bar under the pointer; the readout switches to that day.
    @State private var focusedDay: ListeningLog.Day?

    var body: some View {
        // Re-evaluated each minute so the greeting and date flip at midnight
        // or 5 pm without a playback event having to nudge them.
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .task(id: app.activeServerID) { await app.loadListeningStats() }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let week = ListeningLog.week(endingAt: now, local: app.listening.days, server: app.serverListeningDays)
        let weekTotal = week.reduce(0) { $0 + $1.seconds }
        let streak = ListeningLog.streak(endingAt: now, local: app.listening.days, server: app.serverListeningDays)
        let today = week.last?.seconds ?? 0

        HStack(alignment: .top, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                greeting(now: now, todaySeconds: today)
                HStack(alignment: .bottom, spacing: Theme.Space.l) {
                    WeekBars(week: week, entered: entered, focused: $focusedDay)
                    readout(weekTotal: weekTotal, streak: streak)
                }
                // One VoiceOver stop for the whole chart: hover is the only
                // per-bar interaction, and it has no accessible equivalent.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(weekSummary(weekTotal: weekTotal, streak: streak))
            }
            Spacer(minLength: Theme.Space.l)
            // Only when there's a library to summarize — a 0/0 ring reads as an
            // unfinished artifact.
            if app.libraryTotal > 0 {
                LibraryRing(progress: app.libraryCompletion,
                            finished: app.finishedCount,
                            total: app.libraryTotal,
                            inProgress: app.inProgressCount,
                            entered: entered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard !entered else {
                shownWeekSeconds = weekTotal
                return
            }
            ListeningHeader.hasEntered = true
            // Bars first, then the number catches up a beat later — one read
            // order, not everything moving at once.
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) { entered = true }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.9).delay(0.15)) { shownWeekSeconds = weekTotal }
        }
        .onChange(of: weekTotal) { _, total in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { shownWeekSeconds = total }
        }
    }

    // MARK: Greeting

    private func greeting(now: Date, todaySeconds: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: Self.symbol(at: now))
                    .font(.system(size: 30, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .symbolEffect(.breathe, isActive: !reduceMotion)
                    .accessibilityHidden(true)
                Text(GreetingHeader.greeting(at: now))
                    .font(.system(size: 34, weight: .bold))
            }
            Text(dateLine(now: now, todaySeconds: todaySeconds))
                .font(.title3)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                // Keyed on whole minutes: the sentence only changes when a
                // minute lands, so every change is a real digit roll.
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: Int(todaySeconds / 60))
        }
        .accessibilityElement(children: .combine)
    }

    /// Date and today's total in one sentence — the date earns its place as
    /// context for the number, instead of sitting above the heading as a label.
    private func dateLine(now: Date, todaySeconds: Double) -> String {
        let date = now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if let listened = durationString(todaySeconds), todaySeconds >= 60 {
            return "\(date) · \(listened) listened today"
        }
        return "\(date) · \(app.heroContinue != nil ? "Pick up where you left off." : "Find your next listen.")"
    }

    /// Mirrors `GreetingHeader.greeting(at:)`'s bands (morning 5–12, afternoon
    /// 12–17, evening otherwise), split a little finer where the sky changes.
    static func symbol(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<9: return "sunrise.fill"
        case 9..<17: return "sun.max.fill"
        case 17..<21: return "sunset.fill"
        default: return "moon.stars.fill"
        }
    }

    // MARK: Readout

    private func readout(weekTotal: Double, streak: Int) -> some View {
        let seconds = focusedDay?.seconds ?? shownWeekSeconds
        let caption = focusedDay.map { $0.date.formatted(.dateTime.weekday(.wide)) } ?? "this week"
        return VStack(alignment: .leading, spacing: 2) {
            Text(durationString(seconds) ?? "0 min")
                .font(.title.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)
            if streak >= 2 {
                Label {
                    Text("\(streak)-day streak")
                } icon: {
                    // Its own style: a monochrome symbol takes a Label's
                    // *first* foreground style, which would make it white.
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                        // A frozen trigger value means no bounce under Reduce Motion.
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : streak)
                }
                .font(.callout.weight(.medium))
                .padding(.top, Theme.Space.xs)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.3), value: focusedDay)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: streak >= 2)
    }

    private func weekSummary(weekTotal: Double, streak: Int) -> String {
        var text = "This week, \(spokenDuration(weekTotal)) listened"
        if streak >= 2 { text += "; \(streak)-day streak" }
        return text
    }
}

/// The seven days ending today as capsules, oldest first; today in accent,
/// the rest quiet. Bars grow in with a short stagger on the first appearance
/// and today's bar keeps growing as listening accumulates.
private struct WeekBars: View {
    let week: [ListeningLog.Day]
    let entered: Bool
    @Binding var focused: ListeningLog.Day?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxHeight: CGFloat = 64
    private let barWidth: CGFloat = 20
    /// A zero day still gets a dot, so the week reads as seven days, not gaps.
    private let dot: CGFloat = 4

    var body: some View {
        let peak = max(week.map(\.seconds).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: Theme.Space.s) {
            ForEach(Array(week.enumerated()), id: \.element.id) { index, day in
                bar(day, index: index, peak: peak)
            }
        }
    }

    private func bar(_ day: ListeningLog.Day, index: Int, peak: Double) -> some View {
        let isToday = index == week.count - 1
        let isFocused = focused == day
        let height = entered ? max(dot, maxHeight * CGFloat(day.seconds / peak)) : dot
        return VStack(spacing: 6) {
            Capsule()
                .fill(color(isToday: isToday, isFocused: isFocused))
                .frame(width: barWidth, height: height)
                .frame(height: maxHeight, alignment: .bottom)
                // Stagger only the entrance; later growth (today ticking up
                // while playing) eases without a delay.
                .animation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.2).delay(Double(index) * 0.05), value: entered)
                .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: day.seconds)
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
        .onHover { focused = $0 ? day : (focused == day ? nil : focused) }
        .help("\(day.date.formatted(.dateTime.weekday(.wide))) · \(durationString(day.seconds) ?? "No listening")")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
    }

    private func color(isToday: Bool, isFocused: Bool) -> Color {
        if isToday { return .accentColor }
        return .primary.opacity(isFocused ? 0.45 : 0.2)
    }
}

/// Bolder sibling of `CompletionRing`: a thicker accent stroke, a percentage
/// that counts up on first appearance, and the finished / in-progress counts
/// as two quiet lines beneath.
private struct LibraryRing: View {
    let progress: Double
    let finished: Int
    let total: Int
    let inProgress: Int
    let entered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 130
    private let stroke: CGFloat = 12

    var body: some View {
        let shown = entered ? progress : 0
        VStack(spacing: Theme.Space.s) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: stroke)
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((shown * 100).rounded()))%")
                    .font(.title.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(width: size, height: size)
            .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: shown)

            VStack(spacing: 1) {
                Text("\(finished) of \(total) finished")
                Text("\(inProgress) in progress")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .snappy, value: finished)
            .animation(reduceMotion ? nil : .snappy, value: inProgress)
        }
        .accessibilityElement()
        .accessibilityLabel("Library \(Int((progress * 100).rounded())) percent complete, \(finished) of \(total) finished, \(inProgress) in progress")
    }
}

/// "6 hours 40 minutes" for VoiceOver, where "hr"/"min" abbreviations read badly.
private func spokenDuration(_ seconds: Double) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    var parts: [String] = []
    if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
    if minutes > 0 || parts.isEmpty { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
    return parts.joined(separator: " ")
}
