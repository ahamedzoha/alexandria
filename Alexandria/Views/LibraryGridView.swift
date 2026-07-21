import SwiftUI

struct LibraryGridView: View {
    @Environment(AppState.self) private var app
    @State private var selected: LibraryItem?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)]

    var body: some View {
        Group {
            if app.isLoading && app.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if app.items.isEmpty {
                ContentUnavailableView(
                    "No items",
                    systemImage: "book.closed",
                    description: Text(app.errorMessage ?? "This library is empty.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(app.items) { item in
                            CoverCell(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = item }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selected) { item in
            ItemDetailView(item: item)
                .frame(minWidth: 440, minHeight: 320)
        }
    }
}

struct CoverCell: View {
    @Environment(AppState.self) private var app
    let item: LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: app.coverURL(itemID: item.id)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .overlay(
                            Image(systemName: "book.closed")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        )
                        .aspectRatio(0.66, contentMode: .fit)
                }
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 3, y: 2)

            Text(item.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(item.author)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
