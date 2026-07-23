import XCTest
@testable import Alexandria

/// DownloadStore's load()/persist() are private and bound to the real
/// Application Support directory, so these tests exercise `DownloadedBook` —
/// the exact Codable model DownloadStore decodes index.json into — which is
/// where the pre-episode migration lives (optional episode fields).
final class DownloadStoreMigrationTests: XCTestCase {
    func testOldIndexEntryDecodesWithNilEpisodeFields() throws {
        // A pre-episode index.json entry: no episodeID / episodeTitle keys.
        let json = """
        [{
            "itemID": "book-1",
            "title": "The Iliad",
            "author": "Homer",
            "coverFileName": "book-1.img",
            "tracks": [
                { "fileName": "0.mp3", "startOffset": 0, "duration": 1200 },
                { "fileName": "1.mp3", "startOffset": 1200, "duration": 900 }
            ],
            "chapters": [{ "start": 0, "end": 1200, "title": "Book I" }],
            "duration": 2100,
            "savedProgress": 45.5,
            "updatedAt": 1700000000
        }]
        """
        let books = try JSONDecoder().decode([DownloadedBook].self, from: Data(json.utf8))
        XCTAssertEqual(books.count, 1)
        let book = try XCTUnwrap(books.first)
        XCTAssertNil(book.episodeID)
        XCTAssertNil(book.episodeTitle)
        XCTAssertEqual(book.id, "book-1")   // composite id stays the plain itemID
        XCTAssertEqual(book.itemID, "book-1")
        XCTAssertEqual(book.tracks.count, 2)
        XCTAssertEqual(book.tracks[1].startOffset, 1200)
        XCTAssertEqual(book.chapters.first?.title, "Book I")
        XCTAssertEqual(book.savedProgress, 45.5)
    }

    func testEpisodeEntryRoundTripsCompositeID() throws {
        let episode = DownloadedBook(
            itemID: "pod-1",
            episodeID: "ep-4",
            episodeTitle: "Episode Four",
            title: "Revolutions",
            author: "Mike Duncan",
            coverFileName: nil,
            tracks: [DownloadedTrack(fileName: "0.mp3", startOffset: 0, duration: 1830)],
            chapters: [],
            duration: 1830,
            savedProgress: 0,
            updatedAt: 1_700_000_000
        )
        XCTAssertEqual(episode.id, "pod-1|ep-4")

        let data = try JSONEncoder().encode([episode])
        let decoded = try JSONDecoder().decode([DownloadedBook].self, from: data)
        XCTAssertEqual(decoded.first?.episodeID, "ep-4")
        XCTAssertEqual(decoded.first?.episodeTitle, "Episode Four")
        XCTAssertEqual(decoded.first?.id, "pod-1|ep-4")
    }
}
