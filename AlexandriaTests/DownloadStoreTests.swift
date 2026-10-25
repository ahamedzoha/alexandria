import XCTest
@testable import Alexandria

/// Downloads end to end against a stubbed server and a temporary folder:
/// all or nothing, authenticated by header, and still there after a relaunch.
@MainActor
final class DownloadStoreTests: XCTestCase {
    private var dir: URL!
    private let server = "https://abs.example"

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func store() -> DownloadStore {
        DownloadStore(baseDir: dir, session: StubURLProtocol.session())
    }

    /// Two tracks; the second has no startOffset, so it must follow the first.
    private func session() -> PlaybackInfo {
        PlaybackInfo(id: "s1", audioTracks: [
            .init(index: 0, startOffset: 0, duration: 100, title: nil, contentUrl: "/api/items/b/file/1", mimeType: nil),
            .init(index: 1, startOffset: nil, duration: 50, title: nil, contentUrl: "/api/items/b/file/2", mimeType: nil),
        ], chapters: [], currentTime: 30, duration: nil)
    }

    private func download(_ store: DownloadStore, cover: URL? = nil) async throws {
        try await store.download(item: try makeItem(id: "b", title: "Book"), session: session(),
                                 serverURL: server, token: "secret", coverURL: cover)
    }

    func testADownloadSavesEveryTrackAndSurvivesARelaunch() async throws {
        StubURLProtocol.respond { _ in (200, Data("audio".utf8)) }
        let first = store()
        try await download(first)

        XCTAssertTrue(first.isDownloaded("b"))
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
        for request in StubURLProtocol.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertNil(request.query("token"))
        }

        let relaunched = store()
        let local = try XCTUnwrap(relaunched.localSession(for: "b"))
        XCTAssertEqual(local.audioTracks.map(\.startOffset), [0, 100])
        XCTAssertEqual(local.duration, 150)
        XCTAssertEqual(local.currentTime, 30)
        for track in local.audioTracks {
            let file = try XCTUnwrap(track.contentUrl.flatMap(URL.init(string:)))
            XCTAssertEqual(try Data(contentsOf: file), Data("audio".utf8))
        }
    }

    func testAFailedTrackLeavesNothingBehind() async throws {
        StubURLProtocol.respond { request in
            request.url?.lastPathComponent == "2" ? (404, Data()) : (200, Data("audio".utf8))
        }
        let store = store()
        do {
            try await download(store)
            XCTFail("expected the download to fail")
        } catch let error as APIError {
            XCTAssertEqual(error.message, "Server returned error 404 for track 2.")
        }
        XCTAssertFalse(store.isDownloaded("b"))
        XCTAssertFalse(store.isDownloading("b"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio/b").path))
    }

    func testAnErrorPageIsNotKeptAsTheCover() async throws {
        let cover = try XCTUnwrap(URL(string: "\(server)/api/items/b/cover"))
        StubURLProtocol.respond { request in
            request.url == cover ? (404, Data("<html>".utf8)) : (200, Data("audio".utf8))
        }
        let store = store()
        try await download(store, cover: cover)
        XCTAssertTrue(store.isDownloaded("b"))
        XCTAssertNil(store.localCoverURL("b"))
    }

    func testRemovingADownloadDeletesItsFiles() async throws {
        let cover = try XCTUnwrap(URL(string: "\(server)/api/items/b/cover"))
        StubURLProtocol.respond { _ in (200, Data("bytes".utf8)) }
        let store = store()
        try await download(store, cover: cover)
        let coverFile = try XCTUnwrap(store.localCoverURL("b"))

        store.remove("b")
        XCTAssertFalse(store.isDownloaded("b"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio/b").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: coverFile.path))
        XCTAssertFalse(self.store().isDownloaded("b"), "the removal is saved")
    }
}
