import Foundation
import CryptoKit

// Book ratings from Audible's catalog API and Open Library, matched to a
// library book and cached on disk. Only the lookup fields leave the Mac:
// title + first author (or the ASIN / ISBN). Matching happens locally.

// MARK: - Store setting

/// Audible storefront for ratings and links — catalog and ratings differ per
/// store. The catalog API lives at "api." + `domain`.
enum AudibleStore: String, CaseIterable, Identifiable, Sendable {
    case automatic, us, uk, canada, australia, germany, france, italy, spain, japan, india

    var id: String { rawValue }

    var domain: String {
        switch self {
        case .automatic: Self.forRegion(Locale.current.region?.identifier).domain
        case .us: "audible.com"
        case .uk: "audible.co.uk"
        case .canada: "audible.ca"
        case .australia: "audible.com.au"
        case .germany: "audible.de"
        case .france: "audible.fr"
        case .italy: "audible.it"
        case .spain: "audible.es"
        case .japan: "audible.co.jp"
        case .india: "audible.in"
        }
    }

    var label: String {
        switch self {
        case .automatic: "Automatic (\(Self.forRegion(Locale.current.region?.identifier).label))"
        case .us: "United States"
        case .uk: "United Kingdom"
        case .canada: "Canada"
        case .australia: "Australia"
        case .germany: "Germany"
        case .france: "France"
        case .italy: "Italy"
        case .spain: "Spain"
        case .japan: "Japan"
        case .india: "India"
        }
    }

    /// The store for a region code; anywhere without its own store uses the US one.
    static func forRegion(_ code: String?) -> AudibleStore {
        switch code {
        case "GB": .uk
        case "CA": .canada
        case "AU", "NZ": .australia
        case "DE", "AT", "CH": .germany
        case "FR": .france
        case "IT": .italy
        case "ES": .spain
        case "JP": .japan
        case "IN": .india
        default: .us
        }
    }
}

// MARK: - Query + results

/// What we know about a book for matching. Only `title`, the first author,
/// `asin` and `isbn` are sent anywhere; the rest is used locally to pick the
/// right edition out of the search results.
struct RatingsQuery: Hashable, Sendable {
    var title: String
    var authors: [String]
    var narrators: [String] = []
    var series: String?
    var sequence: String?
    var language: String?
    var asin: String?
    var isbn: String?

    init(title: String, authors: [String], narrators: [String] = [], series: String? = nil,
         sequence: String? = nil, language: String? = nil, asin: String? = nil, isbn: String? = nil) {
        self.title = title
        self.authors = authors
        self.narrators = narrators
        self.series = series
        self.sequence = sequence
        self.language = language
        self.asin = asin
        self.isbn = isbn
    }

    /// From the server's expanded metadata; the fallbacks cover a detail
    /// fetch that failed (offline) or fields the item never had.
    init(meta: ItemDetail.Media.Meta?, fallbackTitle: String, fallbackAuthor: String, fallbackNarrator: String?) {
        let credited = (meta?.authors ?? []).compactMap(\.name)
        let narrators = meta?.narrators ?? (meta?.narratorName ?? fallbackNarrator)?.components(separatedBy: ", ")
        self.init(title: meta?.title ?? fallbackTitle,
                  authors: credited.isEmpty ? (meta?.authorName ?? fallbackAuthor).components(separatedBy: ", ") : credited,
                  narrators: narrators ?? [],
                  series: meta?.series?.first?.name,
                  sequence: meta?.series?.first?.sequence,
                  language: meta?.language,
                  asin: meta?.asin,
                  isbn: meta?.isbn)
    }
}

struct RatingScore: Codable, Equatable, Sendable {
    let average: Double   // out of 5
    let count: Int
}

struct BookRatings: Codable, Equatable, Sendable {
    struct Audible: Codable, Equatable, Sendable {
        let asin: String
        let domain: String
        let overall: RatingScore
        let story: RatingScore?
        let narration: RatingScore?   // Audible's "performance" rating
        let reviewCount: Int
        var productURL: URL? { URL(string: "https://www.\(domain)/pd/\(asin)") }
    }

    struct OpenLibrary: Codable, Equatable, Sendable {
        let workKey: String   // "/works/OL81628W"
        let score: RatingScore
        var url: URL? { URL(string: "https://openlibrary.org\(workKey)") }
    }

    var audible: Audible?
    var openLibrary: OpenLibrary?
    var isEmpty: Bool { audible == nil && openLibrary == nil }
}

// MARK: - Wire formats

struct AudibleProduct: Decodable, Sendable {
    struct Person: Decodable, Sendable { let name: String? }
    struct Series: Decodable, Sendable {
        let title: String?
        let sequence: String?
    }
    struct Rating: Decodable, Sendable {
        struct Distribution: Decodable, Sendable {
            let averageRating: Double?
            let numRatings: Int?
        }
        let numReviews: Int?
        let overallDistribution: Distribution?
        let performanceDistribution: Distribution?
        let storyDistribution: Distribution?
    }

    let asin: String
    let title: String?
    let language: String?
    let authors: [Person]?
    let narrators: [Person]?
    let series: [Series]?
    let rating: Rating?
}

struct AudibleProductsPage: Decodable, Sendable { let products: [AudibleProduct]? }
struct AudibleProductEnvelope: Decodable, Sendable { let product: AudibleProduct? }

struct OpenLibrarySearch: Decodable, Sendable {
    struct Doc: Decodable, Sendable {
        let key: String?
        let title: String?
        let authorName: [String]?
        let ratingsAverage: Double?
        let ratingsCount: Int?
    }
    let docs: [Doc]?
}

struct OpenLibraryEdition: Decodable, Sendable {
    struct Work: Decodable, Sendable { let key: String? }
    let works: [Work]?
}

struct OpenLibraryRatings: Decodable, Sendable {
    struct Summary: Decodable, Sendable {
        let average: Double?
        let count: Int?
    }
    let summary: Summary?
}

// MARK: - Matching

/// Picks the search result that is actually this book. Search returns every
/// volume of a series and other-language editions, so a candidate must share
/// an author and then either the title, or the series slot and narrator.
enum RatingsMatch {
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let spaced = String(folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        })
        return spaced.split(separator: " ").joined(separator: " ")
    }

    /// The full title plus its halves around a colon, with any (…) / […]
    /// asides removed: "The Dark Tower VII: The Dark Tower" also answers to
    /// "The Dark Tower VII" and "The Dark Tower".
    static func titleVariants(_ title: String) -> Set<String> {
        let bare = withoutAsides(title)
        var variants: Set<String> = [normalize(bare)]
        if let colon = bare.firstIndex(of: ":") {
            variants.insert(normalize(String(bare[..<colon])))
            variants.insert(normalize(String(bare[bare.index(after: colon)...])))
        }
        variants.remove("")
        return variants
    }

    /// Either side's whole title appears among the other's variants.
    static func titlesMatch(_ ours: String, _ theirs: String) -> Bool {
        let mineFull = normalize(withoutAsides(ours)), otherFull = normalize(withoutAsides(theirs))
        return (!mineFull.isEmpty && titleVariants(theirs).contains(mineFull))
            || (!otherFull.isEmpty && titleVariants(ours).contains(otherFull))
    }

    private static func withoutAsides(_ title: String) -> String {
        title.replacingOccurrences(of: "\\s*[(\\[][^)\\]]*[)\\]]", with: "", options: .regularExpression)
    }

    /// Same person: identical normalized names, or same surname and first initial
    /// ("J.K. Rowling" / "JK Rowling").
    static func namesOverlap(_ ours: [String], _ theirs: [String]) -> Bool {
        let a = ours.map(normalize).filter { !$0.isEmpty }
        let b = theirs.map(normalize).filter { !$0.isEmpty }
        for x in a {
            for y in b {
                if x == y { return true }
                let xs = x.split(separator: " "), ys = y.split(separator: " ")
                if let xl = xs.last, let yl = ys.last, xl == yl, xs.first?.first == ys.first?.first { return true }
            }
        }
        return false
    }

    static func sequencesMatch(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        if let x = Double(a), let y = Double(b) { return x == y }
        return normalize(a) == normalize(b)
    }

    static func bestAudible(_ products: [AudibleProduct], for query: RatingsQuery) -> AudibleProduct? {
        var best: (product: AudibleProduct, score: Int, count: Int)?
        for product in products {
            guard namesOverlap(query.authors, (product.authors ?? []).compactMap(\.name)) else { continue }
            if let ours = query.language?.lowercased(), let theirs = product.language?.lowercased(), ours != theirs {
                continue   // a Spanish edition's ratings aren't this book's
            }
            let title = titlesMatch(query.title, product.title ?? "")
            let narrator = namesOverlap(query.narrators, (product.narrators ?? []).compactMap(\.name))
            let series = (product.series ?? []).contains { entry in
                guard let name = query.series, let theirs = entry.title else { return false }
                return normalize(name) == normalize(theirs) && sequencesMatch(query.sequence, entry.sequence)
            }
            guard title || (series && narrator) else { continue }
            let score = (title ? 3 : 0) + (narrator ? 2 : 0) + (series ? 2 : 0)
            let count = product.rating?.overallDistribution?.numRatings ?? 0
            if best == nil || score > best!.score || (score == best!.score && count > best!.count) {
                best = (product, score, count)
            }
        }
        return best?.product
    }

    static func bestOpenLibrary(_ docs: [OpenLibrarySearch.Doc], for query: RatingsQuery) -> OpenLibrarySearch.Doc? {
        docs.first { doc in
            (doc.ratingsCount ?? 0) > 0
                && titlesMatch(query.title, doc.title ?? "")
                && namesOverlap(query.authors, doc.authorName ?? [])
        }
    }
}

// MARK: - Network

enum RatingsClient {
    enum Outcome<Value: Sendable>: Sendable {
        case found(Value)
        case notFound
        case failed   // network / server trouble: worth retrying, not caching

        var value: Value? { if case .found(let v) = self { v } else { nil } }
        var failed: Bool { if case .failed = self { true } else { false } }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            // Open Library asks clients to identify themselves.
            "User-Agent": "Alexandria/\(version) (macOS; +https://github.com/ahamedzoha/alexandria)",
        ]
        return URLSession(configuration: config)
    }()

    /// nil when every source failed; otherwise whatever matched (maybe nothing).
    /// Persisted to disk only when no source failed.
    static func lookup(_ query: RatingsQuery, domain: String, cacheKey: String) async -> BookRatings? {
        async let audibleOutcome = audible(query, domain: domain)
        async let openLibraryOutcome = openLibrary(query)
        let (audible, openLibrary) = await (audibleOutcome, openLibraryOutcome)
        if audible.failed && openLibrary.failed { return nil }
        let ratings = BookRatings(audible: audible.value, openLibrary: openLibrary.value)
        if !audible.failed && !openLibrary.failed { RatingsDiskCache.write(ratings, key: cacheKey) }
        return ratings
    }

    private static func audible(_ query: RatingsQuery, domain: String) async -> Outcome<BookRatings.Audible> {
        let groups = "rating,contributors,product_desc,product_attrs,series"
        let base = "https://api.\(domain)/1.0/catalog/products"

        // The server's ASIN is authoritative; an unknown one comes back with
        // zero ratings, and then a search may still find this store's edition.
        if let asin = query.asin, !asin.isEmpty {
            switch await fetch(AudibleProductEnvelope.self, url("\(base)/\(asin)", ["response_groups": groups])) {
            case .found(let envelope):
                if let product = envelope.product, let ratings = summary(product, domain: domain) {
                    return .found(ratings)
                }
            case .notFound: break
            case .failed: return .failed
            }
        }

        var params = ["title": query.title, "num_results": "10",
                      "products_sort_by": "Relevance", "response_groups": groups]
        if let author = query.authors.first { params["author"] = author }
        switch await fetch(AudibleProductsPage.self, url(base, params)) {
        case .found(let page):
            guard let product = RatingsMatch.bestAudible(page.products ?? [], for: query),
                  let ratings = summary(product, domain: domain) else { return .notFound }
            return .found(ratings)
        case .notFound: return .notFound
        case .failed: return .failed
        }
    }

    static func summary(_ product: AudibleProduct, domain: String) -> BookRatings.Audible? {
        func score(_ d: AudibleProduct.Rating.Distribution?) -> RatingScore? {
            guard let d, let average = d.averageRating, let count = d.numRatings, count > 0 else { return nil }
            return RatingScore(average: average, count: count)
        }
        guard let overall = score(product.rating?.overallDistribution) else { return nil }
        return BookRatings.Audible(asin: product.asin, domain: domain, overall: overall,
                                   story: score(product.rating?.storyDistribution),
                                   narration: score(product.rating?.performanceDistribution),
                                   reviewCount: product.rating?.numReviews ?? 0)
    }

    private static func openLibrary(_ query: RatingsQuery) async -> Outcome<BookRatings.OpenLibrary> {
        // ISBN → edition → work → ratings. Audiobook ISBNs are often missing
        // from Open Library, so a miss falls through to a title search.
        let isbn = (query.isbn ?? "").filter { $0.isNumber || $0 == "X" || $0 == "x" }
        if !isbn.isEmpty {
            switch await fetch(OpenLibraryEdition.self, url("https://openlibrary.org/isbn/\(isbn).json", [:])) {
            case .found(let edition):
                if let key = edition.works?.first?.key {
                    switch await fetch(OpenLibraryRatings.self, url("https://openlibrary.org\(key)/ratings.json", [:])) {
                    case .found(let ratings):
                        if let average = ratings.summary?.average, let count = ratings.summary?.count, count > 0 {
                            return .found(.init(workKey: key, score: RatingScore(average: average, count: count)))
                        }
                    case .notFound: break
                    case .failed: return .failed
                    }
                }
            case .notFound: break
            case .failed: return .failed
            }
        }

        var params = ["title": query.title, "limit": "5",
                      "fields": "key,title,author_name,ratings_average,ratings_count"]
        if let author = query.authors.first { params["author"] = author }
        switch await fetch(OpenLibrarySearch.self, url("https://openlibrary.org/search.json", params)) {
        case .found(let search):
            guard let doc = RatingsMatch.bestOpenLibrary(search.docs ?? [], for: query),
                  let key = doc.key, let average = doc.ratingsAverage, let count = doc.ratingsCount
            else { return .notFound }
            return .found(.init(workKey: key, score: RatingScore(average: average, count: count)))
        case .notFound: return .notFound
        case .failed: return .failed
        }
    }

    private static func url(_ base: String, _ params: [String: String]) -> URL? {
        var comps = URLComponents(string: base)
        if !params.isEmpty {
            comps?.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps?.url
    }

    /// 404 and undecodable bodies are a clean miss; transport errors and
    /// other statuses are failures.
    private static func fetch<T: Decodable & Sendable>(_ type: T.Type, _ url: URL?) async -> Outcome<T> {
        guard let url else { return .notFound }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { return .notFound }
            guard (200..<300).contains(status) else { return .failed }
            guard let value = try? decoder.decode(T.self, from: data) else { return .notFound }
            return .found(value)
        } catch {
            return .failed
        }
    }
}

// MARK: - Cache

/// Caches/Ratings/<sha256>.json. A week for matches; a day for "nothing
/// found", so a book the catalogs add later gets picked up.
enum RatingsDiskCache {
    private struct Entry: Codable {
        let fetchedAt: Date
        let ratings: BookRatings
    }

    static func read(key: String) -> BookRatings? {
        guard let file = file(for: key),
              let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        let lifetime: TimeInterval = entry.ratings.isEmpty ? 86_400 : 7 * 86_400
        return Date().timeIntervalSince(entry.fetchedAt) < lifetime ? entry.ratings : nil
    }

    static func write(_ ratings: BookRatings, key: String) {
        guard let file = file(for: key),
              let data = try? JSONEncoder().encode(Entry(fetchedAt: Date(), ratings: ratings)) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private static func file(for key: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("Ratings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name + ".json")
    }
}

/// Session front door: memory, then disk, then network, with concurrent
/// requests for the same book sharing one lookup.
@MainActor
final class RatingsStore {
    static let shared = RatingsStore()

    private var memory: [String: BookRatings] = [:]
    private var inFlight: [String: Task<BookRatings?, Never>] = [:]

    private init() {}

    /// nil when the lookup failed outright (offline); empty when nothing matched.
    func ratings(for query: RatingsQuery, store: AudibleStore) async -> BookRatings? {
        let domain = store.domain
        let key = Self.cacheKey(query, domain: domain)
        if let hit = memory[key] { return hit }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task.detached { () -> BookRatings? in
            if let cached = RatingsDiskCache.read(key: key) { return cached }
            return await RatingsClient.lookup(query, domain: domain, cacheKey: key)
        }
        inFlight[key] = task
        let ratings = await task.value
        inFlight[key] = nil
        if let ratings { memory[key] = ratings }
        return ratings
    }

    private static func cacheKey(_ q: RatingsQuery, domain: String) -> String {
        [domain, q.asin ?? "", q.isbn ?? "", q.title, q.authors.joined(separator: ","),
         q.narrators.joined(separator: ","), q.series ?? "", q.sequence ?? "", q.language ?? ""]
            .joined(separator: "|")
    }
}
