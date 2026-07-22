import Foundation

struct APIError: Error, Sendable {
    let message: String
}

/// Thin async wrapper over the audiobookshelf REST API.
/// Docs: https://api.audiobookshelf.org/
struct APIClient: Sendable {
    let serverURL: String
    let token: String?

    // MARK: URL building

    private func makeURL(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var comps = URLComponents(string: serverURL.trimmingCharacters(in: .whitespaces)) else {
            throw APIError(message: "Invalid server URL.")
        }
        guard comps.scheme != nil else {
            throw APIError(message: "Server URL must start with http:// or https://")
        }
        var basePath = comps.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        comps.path = basePath + "/" + path
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError(message: "Could not build request URL.") }
        return url
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil, auth: Bool = true) throws -> URLRequest {
        var req = URLRequest(url: try makeURL(path))
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if auth, let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            #if DEBUG
            print("[Alexandria] network error for \(req.url?.absoluteString ?? "?"): \(error)")
            #endif
            throw APIError(message: "Could not reach server. Check the URL and that the server is running.")
        }
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "No response from server.") }
        guard (200..<300).contains(http.statusCode) else {
            #if DEBUG
            let bodyText = String(data: data, encoding: .utf8)?.prefix(400) ?? ""
            print("[Alexandria] \(req.httpMethod ?? "?") \(req.url?.absoluteString ?? "?") -> \(http.statusCode)\n\(bodyText)")
            #endif
            if http.statusCode == 401 { throw APIError(message: "Wrong username or password.") }
            throw APIError(message: "Server returned error \(http.statusCode).")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(message: "Unexpected response from server.")
        }
    }

    // MARK: Endpoints

    func login(username: String, password: String) async throws -> String {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = try JSONEncoder().encode(["username": cleanUser, "password": password])
        let req = try request("login", method: "POST", body: body, auth: false)
        let resp = try await send(req, as: LoginResponse.self)
        guard let token = resp.user.token, !token.isEmpty else {
            throw APIError(message: "Login succeeded but no token was returned.")
        }
        return token
    }

    func libraries() async throws -> [Library] {
        let req = try request("api/libraries")
        return try await send(req, as: LibrariesResponse.self).libraries
    }

    func mediaProgress() async throws -> [MediaProgress] {
        let req = try request("api/me")
        return try await send(req, as: MeResponse.self).mediaProgress ?? []
    }

    func items(libraryID: String) async throws -> [LibraryItem] {
        var req = try request("api/libraries/\(libraryID)/items")
        // add paging + sort as query
        if var comps = URLComponents(url: req.url!, resolvingAgainstBaseURL: false) {
            comps.queryItems = [
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(name: "sort", value: "media.metadata.title"),
            ]
            if let u = comps.url { req.url = u }
        }
        return try await send(req, as: ItemsResponse.self).results
    }

    /// Newest-added items first (for the Home "Recently Added" shelf).
    func recentlyAdded(libraryID: String, limit: Int = 20) async throws -> [LibraryItem] {
        var req = try request("api/libraries/\(libraryID)/items")
        if var comps = URLComponents(url: req.url!, resolvingAgainstBaseURL: false) {
            comps.queryItems = [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "sort", value: "addedAt"),
                URLQueryItem(name: "desc", value: "1"),
            ]
            if let u = comps.url { req.url = u }
        }
        return try await send(req, as: ItemsResponse.self).results
    }

    func authors(libraryID: String) async throws -> [AuthorRef] {
        let req = try request("api/libraries/\(libraryID)/authors")
        return try await send(req, as: AuthorsResponse.self).authors
    }

    func authorImageURL(authorID: String) -> URL? {
        var query: [URLQueryItem] = []
        if let token, !token.isEmpty { query.append(URLQueryItem(name: "token", value: token)) }
        return try? makeURL("api/authors/\(authorID)/image", query: query)
    }

    func libraryStats(libraryID: String) async throws -> LibraryStats {
        let req = try request("api/libraries/\(libraryID)/stats")
        return try await send(req, as: LibraryStats.self)
    }

    func itemDetail(itemID: String) async throws -> ItemDetail {
        var req = try request("api/items/\(itemID)")
        if let url = req.url, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = [URLQueryItem(name: "expanded", value: "1")]
            if let u = comps.url { req.url = u }
        }
        return try await send(req, as: ItemDetail.self)
    }

    func coverURL(itemID: String) -> URL? {
        var query: [URLQueryItem] = []
        if let token, !token.isEmpty { query.append(URLQueryItem(name: "token", value: token)) }
        return try? makeURL("api/items/\(itemID)/cover", query: query)
    }

    func play(itemID: String) async throws -> PlaybackInfo {
        let body = try JSONEncoder().encode(PlayRequest())
        let req = try request("api/items/\(itemID)/play", method: "POST", body: body)
        return try await send(req, as: PlaybackInfo.self)
    }

    /// Save listening position back to the server (resumes here + on other devices).
    func updateProgress(itemID: String, currentTime: Double, duration: Double) async throws {
        let progress = duration > 0 ? min(1, currentTime / duration) : 0
        let payload = ProgressUpdate(
            currentTime: currentTime,
            duration: duration,
            progress: progress,
            isFinished: progress >= 0.99
        )
        let body = try JSONEncoder().encode(payload)
        let req = try request("api/me/progress/\(itemID)", method: "PATCH", body: body)
        _ = try await URLSession.shared.data(for: req)
    }
}
