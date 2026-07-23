import XCTest
@testable import Alexandria

final class PodcastModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testExpandedEpisodeDecodesAudioFileAndDuration() throws {
        let json = """
        {
            "id": "ep-1",
            "libraryItemId": "item-1",
            "index": 3,
            "season": "2",
            "episode": "14",
            "title": "The Fall of Carthage",
            "publishedAt": 1700000000000,
            "addedAt": 1700000500000,
            "duration": 1830.5,
            "size": 43821000,
            "audioFile": {
                "ino": "128371",
                "duration": 1830.5,
                "mimeType": "audio/mpeg",
                "metadata": { "filename": "episode-14.mp3", "size": 43821000 }
            }
        }
        """
        let episode = try decode(PodcastEpisode.self, json)
        XCTAssertEqual(episode.id, "ep-1")
        XCTAssertEqual(episode.libraryItemId, "item-1")
        XCTAssertEqual(episode.duration, 1830.5)
        XCTAssertEqual(episode.audioFile?.duration, 1830.5)
        XCTAssertEqual(episode.audioFile?.mimeType, "audio/mpeg")
        XCTAssertEqual(episode.audioFile?.metadata?.filename, "episode-14.mp3")
        XCTAssertEqual(episode.bestDuration, 1830.5)
        XCTAssertEqual(episode.displayTitle, "The Fall of Carthage")
    }

    func testBestDurationFallsBackToAudioFileDuration() throws {
        let json = """
        { "id": "ep-2", "audioFile": { "ino": "1", "duration": 640, "mimeType": "audio/mpeg", "metadata": null } }
        """
        let episode = try decode(PodcastEpisode.self, json)
        XCTAssertNil(episode.duration)
        XCTAssertEqual(episode.bestDuration, 640)
    }

    func testRecentEpisodesDecodesNestedPodcastShell() throws {
        let json = """
        {
            "episodes": [{
                "id": "ep-7",
                "libraryItemId": "pod-1",
                "title": "Episode Seven",
                "publishedAt": 1700000000000,
                "podcast": {
                    "metadata": { "title": "Revolutions", "author": "Mike Duncan" },
                    "coverPath": "/metadata/items/pod-1/cover.jpg",
                    "numEpisodes": 27
                }
            }],
            "total": 1,
            "limit": 25,
            "page": 0
        }
        """
        let response = try decode(RecentEpisodesResponse.self, json)
        XCTAssertEqual(response.episodes.count, 1)
        XCTAssertEqual(response.total, 1)
        let episode = try XCTUnwrap(response.episodes.first)
        XCTAssertEqual(episode.podcast?.metadata?.title, "Revolutions")
        XCTAssertEqual(episode.podcast?.metadata?.author, "Mike Duncan")
        XCTAssertEqual(episode.podcast?.coverPath, "/metadata/items/pod-1/cover.jpg")
        XCTAssertEqual(episode.podcast?.numEpisodes, 27)
    }

    func testMediaProgressDecodesEpisodeId() throws {
        let json = """
        {
            "libraryItemId": "pod-1",
            "episodeId": "ep-9",
            "progress": 0.42,
            "isFinished": false,
            "lastUpdate": 1700000000000
        }
        """
        let progress = try decode(MediaProgress.self, json)
        XCTAssertEqual(progress.libraryItemId, "pod-1")
        XCTAssertEqual(progress.episodeId, "ep-9")
        XCTAssertEqual(progress.progress, 0.42)
        XCTAssertEqual(progress.isFinished, false)
        XCTAssertEqual(progress.lastUpdate, 1700000000000)
    }

    func testLibraryItemDecodesPodcastMediaTypeAndEpisodeCount() throws {
        let json = """
        {
            "id": "pod-1",
            "mediaType": "podcast",
            "addedAt": 1700000000000,
            "media": {
                "metadata": { "title": "Revolutions", "author": "Mike Duncan" },
                "numEpisodes": 27
            }
        }
        """
        let item = try decode(LibraryItem.self, json)
        XCTAssertTrue(item.isPodcast)
        XCTAssertEqual(item.numEpisodes, 27)
        XCTAssertEqual(item.title, "Revolutions")
        XCTAssertEqual(item.author, "Mike Duncan")   // podcast plain-author fallback
        XCTAssertNil(item.duration)
    }

    func testEpisodeDecodesWithOnlyID() throws {
        let episode = try decode(PodcastEpisode.self, #"{ "id": "ep-min" }"#)
        XCTAssertEqual(episode.id, "ep-min")
        XCTAssertNil(episode.title)
        XCTAssertNil(episode.publishedAt)
        XCTAssertNil(episode.addedAt)
        XCTAssertNil(episode.audioFile)
        XCTAssertNil(episode.podcast)
        XCTAssertNil(episode.bestDuration)
        XCTAssertNil(episode.publishedDate)
        XCTAssertEqual(episode.displayTitle, "Untitled episode")
    }

    func testSortDateFallsBackFromPublishedAtToAddedAtToZero() throws {
        let published = try makeEpisode(id: "e1", publishedAt: 1_700_000_000_000, addedAt: 1_600_000_000_000)
        XCTAssertEqual(published.sortDate, 1_700_000_000_000)

        let addedOnly = try makeEpisode(id: "e2", addedAt: 1_600_000_000_000)
        XCTAssertEqual(addedOnly.sortDate, 1_600_000_000_000)

        let neither = try makeEpisode(id: "e3")
        XCTAssertEqual(neither.sortDate, 0)
    }
}
