import XCTest
@testable import Alexandria

/// Working offline: the saved library, telling "offline" from other
/// failures, the cover cache's limit, and download sizes.
final class OfflineTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Snapshot

    func testASnapshotRoundTripsEverythingTheLibraryNeeds() throws {
        let store = LibrarySnapshotStore(directory: dir)
        let book = try makeItem(id: "b1", title: "The Gunslinger", author: "Stephen King", series: "The Dark Tower")
        let show = try makeItem(id: "s1", mediaType: "podcast", title: "Radio Rental")
        let episode = try makeEpisode(id: "e1", libraryItemId: "s1", title: "Episode 17")
        var snapshot = LibrarySnapshot()
        snapshot.libraries = [Library(id: "l1", name: "Audiobooks", mediaType: "book")]
        snapshot.selectedLibraryID = "l1"
        snapshot.itemsByLibrary = ["l1": [book]]
        snapshot.progress = [
            .init(key: .init(itemID: "b1", episodeID: nil), progress: .init(fraction: 0.4, isFinished: false, lastUpdate: 10)),
            .init(key: .init(itemID: "s1", episodeID: "e1"), progress: .init(fraction: 1, isFinished: true, lastUpdate: 20)),
        ]
        snapshot.episodesByItem = ["s1": [episode]]
        snapshot.episodeResumes = [.init(episode: episode, item: show)]
        snapshot.extraItems = [show]

        try store.save(snapshot, serverID: "srv")
        let loaded = try XCTUnwrap(store.load(serverID: "srv"))
        XCTAssertEqual(loaded.libraries.map(\.name), ["Audiobooks"])
        XCTAssertEqual(loaded.itemsByLibrary["l1"]?.first?.title, "The Gunslinger")
        XCTAssertEqual(loaded.progressMap[.init(itemID: "b1", episodeID: nil)]?.fraction, 0.4)
        XCTAssertEqual(loaded.progressMap[.init(itemID: "s1", episodeID: "e1")]?.isFinished, true)
        XCTAssertEqual(loaded.episodeResumes.first?.item.title, "Radio Rental")
        XCTAssertEqual(loaded.episodesByItem["s1"]?.first?.id, "e1")
    }

    func testEachServerHasItsOwnSnapshot() throws {
        let store = LibrarySnapshotStore(directory: dir)
        var home = LibrarySnapshot()
        home.libraries = [Library(id: "l1", name: "Home", mediaType: "book")]
        try store.save(home, serverID: "a")
        XCTAssertNil(store.load(serverID: "b"))
        store.remove(serverID: "a")
        XCTAssertNil(store.load(serverID: "a"))
    }

    func testAnUnreadableSnapshotIsIgnored() throws {
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("srv.json"))
        XCTAssertNil(LibrarySnapshotStore(directory: dir).load(serverID: "srv"))
    }

    // MARK: Offline vs other failures

    func testOnlyTransportFailuresMeanOffline() async {
        let client = APIClient(serverURL: "https://abs.example", token: "t", session: StubURLProtocol.session())

        StubURLProtocol.respond { _ in throw URLError(.notConnectedToInternet) }
        let offline = await failure { _ = try await client.libraries() }
        XCTAssertEqual(offline?.unreachable, true)

        StubURLProtocol.respond { _ in (500, Data()) }
        let serverError = await failure { _ = try await client.libraries() }
        XCTAssertEqual(serverError?.unreachable, false)

        StubURLProtocol.respond { _ in (401, Data()) }
        let expired = await failure { _ = try await client.libraries() }
        XCTAssertEqual(expired?.unreachable, false)
    }

    private func failure(_ work: () async throws -> Void) async -> APIError? {
        do { try await work(); return nil } catch { return error as? APIError }
    }

    // MARK: Cover cache limit

    func testTrimRemovesTheLeastRecentlyUsedFirst() throws {
        let names = ["old", "middle", "new"]
        var files: [URL] = []
        for (age, name) in names.enumerated() {
            var file = dir.appendingPathComponent(name)
            try Data(repeating: 0, count: 64 * 1024).write(to: file)
            var values = URLResourceValues()
            values.contentAccessDate = Date(timeIntervalSinceNow: Double(age - 3) * 86_400)
            try file.setResourceValues(values)
            files.append(file)
        }
        let one = (try XCTUnwrap(files[0].resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize))
        CoverCache.trim(files, to: Int64(one * 2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: files[0].path), "least recently used goes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[1].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[2].path))
    }

    func testDirectorySizeCountsNestedFiles() throws {
        let nested = dir.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10_000).write(to: nested.appendingPathComponent("x"))
        try Data(repeating: 1, count: 10_000).write(to: dir.appendingPathComponent("y"))
        XCTAssertGreaterThanOrEqual(directorySize(dir), 20_000)
    }
}

/// Download sizes and the records Downloads plays from.
@MainActor
final class DownloadsPageTests: XCTestCase {
    func testDownloadSizesAreMeasured() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        StubURLProtocol.respond { _ in (200, Data(repeating: 7, count: 50_000)) }
        let store = DownloadStore(baseDir: dir, session: StubURLProtocol.session())
        let session = PlaybackInfo(id: "s", audioTracks: [
            .init(index: 0, startOffset: 0, duration: 60, title: nil, contentUrl: "/api/items/b/file/1", mimeType: nil),
        ], chapters: [], currentTime: 0, duration: 60)
        try await store.download(item: try makeItem(id: "b", title: "Book"), session: session,
                                 serverURL: "https://abs.example", token: "t", coverURL: nil)
        await store.refreshSizes()
        XCTAssertGreaterThanOrEqual(store.sizes["b"] ?? 0, 50_000)
        XCTAssertGreaterThanOrEqual(store.totalSize, 50_000)
    }

    func testADownloadWithoutAKnownItemIsRebuiltFromItsRecord() throws {
        let record = DownloadedBook(itemID: "never-seen", episodeID: nil, episodeTitle: nil,
                                    title: "Old Download", author: "Somebody", coverFileName: nil,
                                    tracks: [], chapters: [], duration: 100, savedProgress: 0, updatedAt: 0)
        let item = try XCTUnwrap(AppState.rebuiltItem(for: record))
        XCTAssertEqual(item.id, "never-seen")
        XCTAssertEqual(item.title, "Old Download")
        XCTAssertEqual(item.author, "Somebody")
        XCTAssertFalse(item.isPodcast)
    }
}

/// Items fetched one at a time (GET api/items/{id}) list their authors,
/// narrators and series instead of joining them.
final class FullItemShapeTests: XCTestCase {
    func testTheFullItemShapeStillNamesAuthorsAndSeries() throws {
        let json = """
        { "id": "b1", "mediaType": "book", "media": { "metadata": {
            "title": "The Gunslinger",
            "authors": [{ "id": "a1", "name": "Stephen King" }],
            "narrators": ["George Guidall"],
            "series": [{ "id": "s1", "name": "The Dark Tower", "sequence": "1" }] } } }
        """
        let item = try JSONDecoder().decode(LibraryItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.author, "Stephen King")
        XCTAssertEqual(item.narrator, "George Guidall")
        XCTAssertEqual(item.seriesBaseName, "The Dark Tower")
        XCTAssertEqual(item.seriesSequence(in: "The Dark Tower"), 1)
    }

    func testAnUnexpectedListShapeDoesNotFailTheItem() throws {
        let json = """
        { "id": "b2", "mediaType": "book", "media": { "metadata": {
            "title": "Odd", "authorName": "Someone", "series": "not a list" } } }
        """
        let item = try JSONDecoder().decode(LibraryItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.author, "Someone")
        XCTAssertNil(item.seriesBaseName)
    }
}
