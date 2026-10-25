import XCTest
@testable import Alexandria

/// APIClient against a stubbed server: how requests are built, and how each
/// kind of failure reaches the app.
final class APIClientTests: XCTestCase {
    private func client(_ serverURL: String = "https://abs.example", token: String? = "secret") -> APIClient {
        APIClient(serverURL: serverURL, token: token, session: StubURLProtocol.session())
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func apiError(_ work: () async throws -> Void, file: StaticString = #filePath,
                          line: UInt = #line) async -> APIError? {
        do {
            try await work()
            XCTFail("expected an error", file: file, line: line)
            return nil
        } catch let error as APIError {
            return error
        } catch {
            XCTFail("expected APIError, got \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: Building requests

    func testRequestsJoinTheServerSubpathAndCarryTheToken() async throws {
        StubURLProtocol.respond { _ in (200, self.json(#"{"libraries": [{"id": "l1", "name": "Books"}]}"#)) }
        let libraries = try await client("https://abs.example/abs/").libraries()
        XCTAssertEqual(libraries.map(\.id), ["l1"])
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://abs.example/abs/api/libraries")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testAServerURLWithoutASchemeFailsBeforeAnyRequest() async {
        StubURLProtocol.respond { _ in (200, Data()) }
        let error = await apiError { _ = try await self.client("abs.example").libraries() }
        XCTAssertEqual(error?.message, "Server URL must start with http:// or https://")
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testLibraryItemsArePagedUntilAShortPage() async throws {
        StubURLProtocol.respond { request in
            let count = request.query("page") == "0" ? 500 : 3
            let items = (0..<count).map { #"{"id": "i\#($0)", "mediaType": "book", "media": {"metadata": {}}}"# }
            return (200, Data(#"{"results": [\#(items.joined(separator: ","))]}"#.utf8))
        }
        let items = try await client().items(libraryID: "l1")
        XCTAssertEqual(items.count, 503)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.query("page") }, ["0", "1"])
        XCTAssertEqual(StubURLProtocol.requests.first?.query("limit"), "500")
    }

    func testListeningSessionsAsksForOneLargePage() async throws {
        StubURLProtocol.respond { _ in (200, self.json(#"{"sessions": []}"#)) }
        _ = try await client().listeningSessions()
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/me/listening-sessions")
        XCTAssertEqual(request.query("itemsPerPage"), "200")
        XCTAssertEqual(request.query("page"), "0")
    }

    func testSessionSyncPostsTheListenedTime() async throws {
        StubURLProtocol.respond { _ in (200, Data()) }
        try await client().syncSession(id: "s1", SessionSync(currentTime: 100, timeListened: 15, duration: 600))
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/session/s1/sync")
        let body = try XCTUnwrap(request.bodyData)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Double])
        XCTAssertEqual(sent["timeListened"], 15)
        XCTAssertEqual(sent["currentTime"], 100)
    }

    // MARK: Failures

    func testARejectedTokenAsksTheUserToSignInAgain() async {
        StubURLProtocol.respond { _ in (401, Data()) }
        let error = await apiError { _ = try await self.client().libraries() }
        XCTAssertEqual(error?.status, 401)
        XCTAssertEqual(error?.tokenRejected, true)
    }

    func testAWrongPasswordIsNotAnExpiredSignIn() async {
        StubURLProtocol.respond { _ in (401, Data()) }
        let error = await apiError { _ = try await self.client(token: nil).login(username: "me", password: "nope") }
        XCTAssertEqual(error?.message, "Wrong username or password.")
        XCTAssertEqual(error?.tokenRejected, false)
        XCTAssertNil(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func testServerErrorsKeepTheirStatus() async {
        StubURLProtocol.respond { _ in (503, Data()) }
        let error = await apiError { _ = try await self.client().item(itemID: "x") }
        XCTAssertEqual(error?.status, 503)
        XCTAssertEqual(error?.tokenRejected, false)
    }

    func testAnUndecodableBodyIsAnUnexpectedResponse() async {
        StubURLProtocol.respond { _ in (200, self.json("<html>proxy login</html>")) }
        let error = await apiError { _ = try await self.client().libraries() }
        XCTAssertEqual(error?.message, "Unexpected response from server.")
    }

    func testAnUnreachableServerSaysSo() async {
        StubURLProtocol.respond { _ in throw URLError(.cannotConnectToHost) }
        let error = await apiError { _ = try await self.client().libraries() }
        XCTAssertEqual(error?.message.hasPrefix("Could not reach server."), true)
    }

    func testACancelledRequestIsCancellationNotAFailure() async {
        StubURLProtocol.respond { _ in throw URLError(.cancelled) }
        do {
            _ = try await client().libraries()
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
    }
}

/// Saved servers are matched on one spelling of their address.
final class ServerURLTests: XCTestCase {
    func testSpellingsOfTheSameServerMatch() {
        let canonical = "https://abs.example"
        for spelling in ["https://abs.example/", " HTTPS://ABS.example// ", "https://abs.example:443"] {
            XCTAssertEqual(AppState.normalizedServerURL(spelling), canonical, spelling)
        }
    }

    func testPathsAndPortsThatMatterAreKept() {
        XCTAssertEqual(AppState.normalizedServerURL("http://NAS.local:13378/ABS/"), "http://nas.local:13378/ABS")
        XCTAssertEqual(AppState.normalizedServerURL("http://abs.example:443"), "http://abs.example:443")
    }
}

extension URLRequest {
    /// The body as the server receives it: URLSession hands protocols a
    /// stream rather than `httpBody`.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
