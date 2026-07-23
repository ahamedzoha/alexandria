import XCTest
@testable import Alexandria

final class NextEpisodeOrderingTests: XCTestCase {
    func testNextEpisodeOrdering() throws {
        // AppState.nextEpisode(after:in:) is an instance method, and
        // AppState's init is not side-effect free in a unit test: it loads
        // persisted servers from UserDefaults, constructs a DownloadStore
        // (which reads and sweeps the real Application Support directory),
        // and starts the 45-second network sync loop when a login exists on
        // this machine. Revisit once the ordering logic is exposed as a pure
        // function over ([PodcastEpisode], progress).
        throw XCTSkip("AppState is not constructible without side effects; next-episode selection is not exposed as a pure function.")
    }
}
