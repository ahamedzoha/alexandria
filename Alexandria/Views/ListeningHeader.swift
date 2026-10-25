import SwiftUI

/// Home's opening moment: a time-of-day greeting, today's listening folded
/// into the date line, the last seven days as a small bar chart with a live
/// readout and streak, and the library-completion ring. Bold through type
/// scale, real numbers and one authored entrance (bars grow, numerals roll),
/// not through decoration — the page stays on the plain window background.
struct ListeningHeader: View {
    @Environment(AppState.self) private var app
    /// Opens a book's details (a click on its mosaic tile).
    var onOpen: (LibraryItem) -> Void = { _ in }
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
            // Books only: a podcast library's items are shows, which don't
            // get finished.
            if app.items.contains(where: { !$0.isPodcast }) {
                LibraryMosaic(entered: entered, onOpen: onOpen)
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

/// The library as covers instead of a percentage: one small tile per book,
/// finished first, then in progress, then the rest — so the colored area
/// *is* the progress, filling from the top left. Finished books are in full
/// color, in-progress ones carry an accent line, unstarted ones wait in
/// grayscale. Hover names a book; click opens it. On first appearance the
/// tiles arrive in a diagonal wave and then the read ones color in.
private struct LibraryMosaic: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entered: Bool
    let onOpen: (LibraryItem) -> Void

    private static let columns = 10
    private static let rows = 6
    private static let tile: CGFloat = 22
    private static let gap: CGFloat = 3

    private enum Status: Int { case finished, inProgress, unread }

    private struct Tile: Identifiable {
        let item: LibraryItem
        let status: Status
        let fraction: Double
        var id: String { item.id }
    }

    /// Books in fill order; past the grid's capacity the last cell says how
    /// many more there are.
    private var tiles: (shown: [Tile], more: Int) {
        let books = app.items.filter { !$0.isPodcast }.map { item -> Tile in
            let p = app.progress(itemID: item.id)
            let status: Status = p?.isFinished == true ? .finished
                : (p?.fraction ?? 0) > 0.001 ? .inProgress : .unread
            return Tile(item: item, status: status, fraction: p?.fraction ?? 0)
        }
        .sorted { ($0.status.rawValue, $0.item.title) < ($1.status.rawValue, $1.item.title) }
        let capacity = Self.columns * Self.rows
        guard books.count > capacity else { return (books, 0) }
        return (Array(books.prefix(capacity - 1)), books.count - (capacity - 1))
    }

    var body: some View {
        let (shown, more) = tiles
        VStack(alignment: .trailing, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(app.finishedCount)")
                    .font(.title2.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \(app.libraryTotal) finished")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .animation(reduceMotion ? nil : .snappy, value: app.finishedCount)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.tile), spacing: Self.gap), count: Self.columns),
                      spacing: Self.gap) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, tile in
                    MosaicTile(tile: tile.item, status: tile.status.rawValue, fraction: tile.fraction,
                               index: index, columns: Self.columns, size: Self.tile, entered: entered)
                        .onTapGesture { onOpen(tile.item) }
                }
                if more > 0 {
                    Text("+\(more)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .frame(width: Self.tile, height: Self.tile)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .help("\(more) more books")
                }
            }
            .frame(width: CGFloat(Self.columns) * (Self.tile + Self.gap) - Self.gap)

            Text("\(app.inProgressCount) in progress · \(max(0, app.libraryTotal - app.finishedCount - app.inProgressCount)) to go")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Library: \(app.finishedCount) of \(app.libraryTotal) books finished, \(app.inProgressCount) in progress")
    }
}

/// One book in the mosaic.
private struct MosaicTile: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tile: LibraryItem
    let status: Int          // 0 finished · 1 in progress · 2 unread
    let fraction: Double
    let index: Int
    let columns: Int
    let size: CGFloat
    let entered: Bool
    @State private var hovering = false

    /// Diagonal wave: cells on the same anti-diagonal arrive together.
    private var waveDelay: Double {
        min(Double(index / columns + index % columns) * 0.025, 0.45)
    }

    var body: some View {
        let colored = status != 2 && entered
        RemoteImage(url: app.coverURL(itemID: tile.id)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } fallback: {
            Rectangle().fill(.quaternary)
        }
        .frame(width: size, height: size)
        // Unread waits in grayscale; read books color in after they land.
        .saturation(colored ? 1 : 0)
        .opacity(status == 2 ? 0.45 : 1)
        .overlay(alignment: .bottom) {
            if status == 1 {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .scaleEffect(x: max(0.08, fraction), anchor: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.hairline))
        .scaleEffect(entered ? (hovering && !reduceMotion ? 1.35 : 1) : 0.6)
        .opacity(entered ? 1 : 0)
        .shadow(color: .black.opacity(hovering ? 0.3 : 0), radius: 4, y: 2)
        .zIndex(hovering ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.25).delay(waveDelay), value: entered)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).delay(waveDelay + 0.35), value: colored)
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .help("\(tile.title) — \(status == 0 ? "finished" : status == 1 ? "\(Int(fraction * 100))% in" : "not started")")
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
