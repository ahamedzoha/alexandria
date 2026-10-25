import SwiftUI

/// Home's opening: the greeting, one editorial line about the week, and a
/// listening diary — the last seven days, each showing the covers of what
/// was actually played that day — beside the library mosaic. Both halves are
/// made of the same material, your books: the left is what you listened to,
/// the right what you've finished.
struct ListeningHeader: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Opens a book's details (a click on a cover).
    var onOpen: (LibraryItem) -> Void = { _ in }

    /// The entrance plays once per launch, like HomeView's own cascade; Home
    /// is rebuilt on every return and replaying it read as a glitch.
    @MainActor private static var hasEntered = false
    @State private var entered = ListeningHeader.hasEntered

    var body: some View {
        // Re-evaluated each minute so the greeting and date roll over at
        // midnight or 5 pm without a playback event to nudge them.
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .task(id: app.activeServerID) { await app.loadListeningStats() }
        .onAppear {
            guard !entered else { return }
            ListeningHeader.hasEntered = true
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) { entered = true }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let week = app.listeningWeek(endingAt: now)
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.l + 4) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(GreetingHeader.greeting(at: now))
                        .font(Theme.Typography.greeting)
                    summary(now: now, week: week)
                }
                ListeningDiary(week: week, entered: entered, title: title(for:), onOpen: open)
            }
            Spacer(minLength: Theme.Space.l)
            if app.libraryHasBooks {
                LibraryMosaic(entered: entered, onOpen: onOpen)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Summary line

    /// "Sunday, 25 October · 37 min this week, mostly Episode 17 · 3 days in a
    /// row" — the date as context, the numbers and the title in primary ink.
    private func summary(now: Date, week: [ListeningLog.Day]) -> some View {
        let date = now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let total = week.reduce(0) { $0 + $1.seconds }
        let streak = ListeningLog.streak(endingAt: now, local: app.listening.totals, server: app.serverListeningDays)
        let top = ListeningLog.mostListened(in: week, local: app.listening.days,
                                            serverItems: app.serverListeningItems).flatMap(title(for:))

        var line: Text
        if total >= 60, let listened = durationString(total) {
            line = Text("\(date) · \(Text(listened).foregroundStyle(.primary)) this week")
            if let top { line = Text("\(line), mostly \(Text(top).italic().foregroundStyle(.primary))") }
        } else {
            line = Text("\(date) · \(app.heroContinue != nil ? "Pick up where you left off." : "Find your next listen.")")
        }
        if streak >= 2 { line = Text("\(line) · \(streak) days in a row") }

        return line
            .font(.title3)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: Int(total / 60))
    }

    private func title(for id: String) -> String? {
        app.listeningTitle(for: id)
    }

    private func open(_ id: String) {
        if let item = app.item(byID: id) { onOpen(item); return }
        Task { if let item = await app.resolveItem(id: id) { onOpen(item) } }
    }
}

/// The last seven days as columns: the day, the covers of what was played
/// (fanned when there were several; an empty slot when nothing was), and the
/// time. Today's column is marked in the accent and fills in live.
private struct ListeningDiary: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let week: [ListeningLog.Day]
    let entered: Bool
    let title: (String) -> String?
    let onOpen: (String) -> Void

    private static let tile: CGFloat = 22   // the mosaic's tile size
    private static let fan: CGFloat = 7     // offset between stacked covers
    private static let maxCovers = 3

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            ForEach(Array(week.enumerated()), id: \.element.id) { index, day in
                column(day, isToday: index == week.count - 1, index: index)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func column(_ day: ListeningLog.Day, isToday: Bool, index: Int) -> some View {
        let covers = Array(day.itemIDs.prefix(Self.maxCovers))
        return VStack(alignment: .leading, spacing: 6) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption.weight(isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : .secondary)

            ZStack(alignment: .leading) {
                if covers.isEmpty {
                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: Self.tile, height: Self.tile)
                }
                // Most-listened in front.
                ForEach(Array(covers.enumerated().reversed()), id: \.element) { depth, id in
                    cover(id)
                        .offset(x: CGFloat(depth) * Self.fan)
                        .zIndex(Double(-depth))
                }
            }
            .frame(width: Self.tile + Self.fan * CGFloat(Self.maxCovers - 1), height: Self.tile, alignment: .leading)
            .opacity(entered ? 1 : 0)
            .offset(y: entered || reduceMotion ? 0 : -6)
            .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.2).delay(Double(index) * 0.05), value: entered)
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: covers)

            Text(compact(day.seconds))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(day.seconds >= 60 ? .secondary : .tertiary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: Int(day.seconds / 60))
        }
        .help(help(for: day))
    }

    private func cover(_ id: String) -> some View {
        RemoteImage(url: app.coverURL(itemID: id)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } fallback: {
            Rectangle().fill(.quaternary)
        }
        .frame(width: Self.tile, height: Self.tile)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.25), radius: 1.5, x: 1, y: 0)
        .onTapGesture { onOpen(id) }
    }

    /// "34m", "1h 12m", "—".
    private func compact(_ seconds: Double) -> String {
        seconds < 60 ? "—" : Format.duration(seconds)
    }

    private func help(for day: ListeningLog.Day) -> String {
        let name = day.date.formatted(.dateTime.weekday(.wide))
        guard day.seconds >= 60 else { return "\(name) · No listening" }
        let titles = day.itemIDs.compactMap(title).joined(separator: ", ")
        return "\(name) · \(durationString(day.seconds) ?? "")" + (titles.isEmpty ? "" : " — \(titles)")
    }

    private var accessibilitySummary: String {
        let listened = week.filter { $0.seconds >= 60 }
        guard !listened.isEmpty else { return "No listening in the last seven days" }
        return "Last seven days: " + listened.map {
            "\($0.date.formatted(.dateTime.weekday(.wide))) \(spokenDuration($0.seconds))"
        }.joined(separator: ", ")
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
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).strokeBorder(Theme.hairline))
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
