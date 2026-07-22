import SwiftUI

// MARK: - Series (stacked-cover cards)

struct SeriesGridView: View {
    @Environment(AppState.self) private var app

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 28)]

    private struct SeriesGroup: Identifiable {
        let id: String
        let count: Int
        let coverItemIDs: [String]
        var name: String { id }
    }

    private var groups: [SeriesGroup] {
        var buckets: [String: [String]] = [:]
        for item in app.items {
            if let key = item.seriesBaseName, !key.isEmpty { buckets[key, default: []].append(item.id) }
        }
        return buckets
            .map { SeriesGroup(id: $0.key, count: $0.value.count, coverItemIDs: Array($0.value.prefix(3))) }
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
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(groups) { group in
                            Button {
                                app.showGroup(kind: .series, value: group.name)
                            } label: {
                                SeriesCard(name: group.name, count: group.count, coverIDs: group.coverItemIDs)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(group.name), \(group.count) books")
                        }
                    }
                    .padding(28)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                // Peek cards behind the primary cover imply a stack.
                ForEach(Array(coverIDs.dropFirst().prefix(2).enumerated()), id: \.offset) { index, id in
                    let depth = CGFloat(index + 1)
                    cover(id)
                        .scaleEffect(1 - depth * 0.06)
                        .offset(y: -depth * 10)
                        .brightness(-0.15 * depth)
                        .zIndex(-depth)
                }
                if let first = coverIDs.first {
                    cover(first).zIndex(1)
                }
            }
            .frame(height: 210)
            .hoverLift(cornerRadius: 8)

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(count) book\(count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func cover(_ id: String) -> some View {
        RemoteImage(url: app.coverURL(itemID: id)) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } fallback: {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
        }
        .frame(width: 160, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}

// MARK: - People (authors / narrators as avatar cards)

struct PeopleGridView: View {
    @Environment(AppState.self) private var app
    let kind: AppState.Browse   // .authors or .narrators

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)]

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
                                PersonCard(name: person.name, count: person.count, imageURL: person.imageURL)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(person.name), \(person.count) books")
                        }
                    }
                    .padding(28)
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

    var body: some View {
        VStack(spacing: 10) {
            avatar
                .frame(width: 108, height: 108)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .hoverLift()

            VStack(spacing: 2) {
                Text(name).font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center).lineLimit(2)
                Text("\(count) book\(count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
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

    private var gradientColors: [Color] {
        let palette: [[Color]] = [
            [.indigo, .purple], [.blue, .teal], [.pink, .orange],
            [.teal, .green], [.orange, .red], [.purple, .pink], [.cyan, .blue],
        ]
        let seed = name.utf8.reduce(0) { $0 &+ Int($1) }
        return palette[seed % palette.count]
    }
}
