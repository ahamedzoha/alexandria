import XCTest
@testable import Alexandria

/// 0.5.6: tokens out of URLs, bounded cover fetching, and Alexandria's own
/// sessions kept out of the diary's server totals.
final class NetworkHygieneTests: XCTestCase {
    func testDownloadsAuthenticateWithAHeaderNotTheURL() throws {
        let request = try XCTUnwrap(DownloadStore.trackRequest("/api/items/x/file/1", serverURL: "https://abs.example/",
                                                               token: "secret"))
        XCTAssertEqual(request.url?.absoluteString, "https://abs.example/api/items/x/file/1")
        XCTAssertFalse(request.url?.absoluteString.contains("secret") ?? true, "the token stays out of logs")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testHLSKeepsItsQueryToken() throws {
        let request = try XCTUnwrap(DownloadStore.trackRequest("/hls/abc/output.m3u8", serverURL: "https://abs.example",
                                                               token: "secret"))
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "token" }?.value, "secret")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testFetchGateNeverRunsMoreThanItsLimit() async {
        let gate = FetchGate(limit: 2)
        let counter = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await gate.acquire()
                    await counter.enter()
                    try? await Task.sleep(for: .milliseconds(20))
                    await counter.leave()
                    await gate.release()
                }
            }
        }
        let peak = await counter.peak
        XCTAssertEqual(peak, 2)
    }

    func testAlexandriaSessionsAreRecognised() throws {
        let decode = { (json: String) in try JSONDecoder().decode(ListeningStats.Session.self, from: Data(json.utf8)) }
        XCTAssertTrue(try decode(#"{ "deviceInfo": { "clientName": "Alexandria" } }"#).isAlexandria)
        XCTAssertFalse(try decode(#"{ "deviceInfo": { "clientName": "plappa" } }"#).isAlexandria)
        XCTAssertFalse(try decode(#"{ }"#).isAlexandria)
    }
}

private actor Counter {
    private(set) var peak = 0
    private var current = 0
    func enter() { current += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}
