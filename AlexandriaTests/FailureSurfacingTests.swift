import XCTest
@testable import Alexandria

/// 0.5.4: failures the user should hear about, and ones they shouldn't.
@MainActor
final class FailureSurfacingTests: XCTestCase {
    func testFailedActionRaisesOneAlertNamingIt() {
        let app = AppState()
        app.presentFailure("Couldn't Play “Dune”", APIError(message: "Server returned error 500.", status: 500))
        XCTAssertEqual(app.actionError?.title, "Couldn't Play “Dune”")
        XCTAssertEqual(app.actionError?.message, "Server returned error 500.")
    }

    func testCancellationIsNotAFailure() {
        let app = AppState()
        app.presentFailure("Couldn't Play “Dune”", CancellationError())
        XCTAssertNil(app.actionError)
    }

    func testDownloadWithAMissingTrackSavesNothing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DownloadStore(baseDir: dir)
        let item = try makeItem(id: "book", title: "Dune", author: "Frank Herbert")
        let session = PlaybackInfo(id: nil, audioTracks: [
            .init(index: 0, startOffset: 0, duration: 60, title: nil, contentUrl: nil, mimeType: nil),
        ], chapters: nil, currentTime: 0, duration: 60)

        do {
            try await store.download(item: item, session: session, serverURL: "http://example.invalid",
                                     token: nil, coverURL: nil)
            XCTFail("a track without a file must fail the download")
        } catch let error as APIError {
            XCTAssertEqual(error.message, "Track 1 has no downloadable file.")
        }
        XCTAssertFalse(store.isDownloaded("book"), "no half-downloaded record that can't play")
        XCTAssertNil(store.downloadProgress("book"), "the progress spinner clears")
    }
}
