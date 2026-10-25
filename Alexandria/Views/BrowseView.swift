import SwiftUI

/// "3 books" / "3 shows" — browse cards describe whatever the selected
/// library holds, not always books.
// MARK: - Series (stacked-cover cards)

struct SeriesGridView: View {
    @Environment(AppState.self) private var app

    // Covers fill their column, so the gutter is the only horizontal space.
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: Theme.Space.l)]

    private struct SeriesGroup: Identifiable {
        let id: String
        let count: Int
        let coverItemIDs: [String]
        var name: String { id }
    }

    private var groups: [SeriesGroup] {
        var buckets: [String: [LibraryItem]] = [:]
        for item in app.items {
            if let key = item.seriesBaseName, !key.isEmpty { buckets[key, default: []].append(item) }
        }
        return buckets
            .map { name, books in
                // Book 1 on top of the stack.
                SeriesGroup(id: name, count: books.count,
                            coverItemIDs: AppState.seriesOrdered(books, series: name).prefix(3).map(\.id))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if app.isLoading && app.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                ContentUnavailableView("No Series Yet", systemImage: "books.vertical",
                                       description: Text("Series appear here once your books include series metadata."))
            } else {
                ScrollView {
                    // Rows already carry the stack headroom above each cover.
                    LazyVGrid(columns: columns, spacing: Theme.Space.l) {
                        ForEach(groups) { group in
                            Button {
                                app.showGroup(kind: .series, value: group.name)
                            } label: {
                                SeriesCard(name: group.name, count: group.count,
                                           coverIDs: group.coverItemIDs, noun: app.mediaNoun)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(group.name), \(Format.count(group.count, app.mediaNoun))")
                        }
                    }
                    .padding(Theme.Space.xl)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SeriesCard: View {
    @Environment(AppState.self) private var app
    let name: String
    let count: Int
    let coverIDs: [String]
    let noun: String

    /// How far each book behind rises above the one in front of it.
    private static let peek: CGFloat = 12
    private static let maxPeeks = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            ZStack(alignment: .top) {
                // Books 2 and 3 rise behind book 1, each a clear strip taller
                // and a step narrower, so the stack reads at a glance.
                ForEach(Array(coverIDs.dropFirst().prefix(Self.maxPeeks).enumerated()), id: \.offset) { index, id in
                    let depth = CGFloat(index + 1)
                    cover(id)
                        .scaleEffect(1 - depth * 0.07, anchor: .top)
                        .offset(y: -depth * Self.peek)
                        .brightness(-0.12 * depth)
                        .zIndex(-depth)
                }
                if let first = coverIDs.first {
                    cover(first).zIndex(1)
                }
            }
            // Same headroom for every card, stacked or single, so covers
            // in a row line up.
            .padding(.top, Self.peek * CGFloat(Self.maxPeeks))
            .hoverLift()

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(Theme.Typography.cardTitle).lineLimit(1)
                    Text(Format.count(count, noun))
                        .font(Theme.Typography.meta).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func cover(_ id: String) -> some View {
        CoverArt(url: app.coverURL(itemID: id), title: name)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.cover, style: .continuous).strokeBorder(Theme.hairline))
        .themeShadow(Theme.Shadow.card)
    }
}

// MARK: - People (authors / narrators as avatar cards)

struct PeopleGridView: View {
    @Environment(AppState.self) private var app
    let kind: AppState.Browse   // .authors or .narrators

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: Theme.Space.l)]

    private struct Person: Identifiable {
        let id: String           // name
        let count: Int
        let imageURL: URL?
        var name: String { id }
    }

    private var people: [Person] {
        if kind == .authors {
            return app.authors
                .map { Person(id: $0.name,
                              count: app.bookCount(forAuthor: $0.name),
                              imageURL: $0.imagePath != nil ? app.authorImageURL(authorID: $0.id) : nil) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } else {
            var counts: [String: Int] = [:]
            for item in app.items {
                if let n = item.narrator, !n.isEmpty { counts[n, default: 0] += 1 }
            }
            return counts
                .map { Person(id: $0.key, count: $0.value, imageURL: nil) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        Group {
            if app.isLoading && app.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if people.isEmpty {
                ContentUnavailableView(kind == .authors ? "No Authors Yet" : "No Narrators Yet",
                                       systemImage: kind == .authors ? "person" : "mic",
                                       description: Text("These appear once your library finishes scanning."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(people) { person in
                            Button {
                                app.showGroup(kind: kind, value: person.name)
                            } label: {
                                PersonCard(name: person.name, count: person.count,
                                           imageURL: person.imageURL, noun: app.mediaNoun)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(person.name), \(Format.count(person.count, app.mediaNoun))")
                        }
                    }
                    .padding(Theme.Space.xl)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: kind) { if kind == .authors { await app.loadAuthors() } }
    }
}

struct PersonCard: View {
    let name: String
    let count: Int
    let imageURL: URL?
    let noun: String

    var body: some View {
        VStack(spacing: 10) {
            avatar
                .frame(width: 108, height: 108)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .hoverLift()

            VStack(spacing: 2) {
                Text(name).font(Theme.Typography.cardTitle)
                    .multilineTextAlignment(.center).lineLimit(2)
                Text(Format.count(count, noun))
                    .font(Theme.Typography.meta).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var avatar: some View {
        if let imageURL {
            RemoteImage(url: imageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } fallback: {
                initials
            }
        } else {
            initials
        }
    }

    private var initials: some View {
        ZStack {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initialsText).font(.title.weight(.semibold)).foregroundStyle(.white)
        }
    }

    private var initialsText: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private var gradientColors: [Color] { Theme.placeholderColors(seed: name) }
}
