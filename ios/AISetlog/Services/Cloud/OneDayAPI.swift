import Foundation

/// The Worker in `workers/api`: every room, clip, message and mood goes
/// through here now that CloudKit is gone.
///
/// Every request carries the 1Day session token from sign-in. There is no
/// user id in any body — the Worker takes it from the token — so the only
/// thing this type decides is which token to send.
struct OneDayAPI {
    enum Failure: Error, Equatable {
        /// No session on this phone, or the Worker no longer accepts it.
        /// Signing in again is the only fix.
        case notSignedIn
        case notFound
        /// The thing already exists (a room code someone else has).
        case conflict
        /// Signed in, but this isn't yours to change.
        case forbidden
        /// No network, timed out, the Worker is down.
        case unavailable
        case badResponse(Int)
    }

    static var shared = OneDayAPI()

    var baseURL: URL = AuthService.defaultBaseURL
    var session: URLSession = .shared
    var keychain: SessionKeychain = .standard
    /// Sent instead of the keychain's session: sign-out uses it to unregister
    /// the phone with the session that is about to be removed.
    var fixedSession: AuthService.Session? = nil
    var timeout: TimeInterval = 30
    /// Uploads are a whole clip.
    var uploadTimeout: TimeInterval = 120

    /// A session with less than this left is swapped for a fresh one.
    static let refreshWindow: TimeInterval = 14 * 24 * 60 * 60

    /// Whether there is a session to send at all. Rooms need one.
    var isSignedIn: Bool {
        guard let saved = keychain.load() else { return false }
        return saved.expiresAt > .now
    }

    /// The author id the app and every stored row use for a session's user:
    /// Apple's bare `sub` (what CloudKit always had), `google:<sub>` as is.
    /// Must match `authorIdFor` in `workers/api/src/http.js`.
    static func authorID(forSessionUser userId: String) -> String {
        userId.hasPrefix("apple:") ? String(userId.dropFirst("apple:".count)) : userId
    }

    // MARK: Requests

    /// Path components are escaped one by one: record names carry dots,
    /// colons and underscores, never a slash.
    func url(_ components: [String], query: [URLQueryItem] = []) -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let path = components
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
            .joined(separator: "/")
        var url = URL(string: baseURL.absoluteString.trimmingSuffix("/") + "/" + path)!
        if !query.isEmpty { url.append(queryItems: query) }
        return url
    }

    @discardableResult
    func send(
        _ method: String, _ components: [String], query: [URLQueryItem] = [],
        json body: (any Encodable)? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url(components, query: query), timeoutInterval: timeout)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        return try await perform(request)
    }

    func get<T: Decodable>(_ type: T.Type, _ components: [String], query: [URLQueryItem] = []) async throws -> T {
        try decode(type, from: await send("GET", components, query: query))
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("[api] undecodable \(T.self): \(error)")
            throw Failure.unavailable
        }
    }

    /// Puts a file in R2 and returns its key, for a clip or member row to
    /// point at.
    func upload(_ file: URL, contentType: String) async throws -> String {
        var request = URLRequest(url: url(["media"]), timeoutInterval: uploadTimeout)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "content-type")
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        request.setValue(String(size), forHTTPHeaderField: "content-length")
        struct Key: Decodable { let key: String }
        let data = try await perform(request, uploading: file)
        return try decode(Key.self, from: data).key
    }

    /// Downloads a file from R2 to `destination`, replacing what's there.
    func download(key: String, to destination: URL) async throws {
        var request = URLRequest(
            url: url(["media"] + key.split(separator: "/").map(String.init)),
            timeoutInterval: uploadTimeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "authorization")
        let (temp, response): (URL, URLResponse)
        do {
            (temp, response) = try await session.download(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Failure.unavailable
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        try check(response)
        try Task.checkCancellation()
        let fm = FileManager.default
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RoomClipCache.install(temp, to: destination, consumingSource: true)
    }

    private func perform(_ request: URLRequest, uploading file: URL? = nil) async throws -> Data {
        var request = request
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "authorization")
        let data: Data
        let response: URLResponse
        do {
            if let file {
                (data, response) = try await session.upload(for: request, fromFile: file)
            } else {
                (data, response) = try await session.data(for: request)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Failure.unavailable
        }
        try check(response)
        return data
    }

    private func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.unavailable }
        switch status {
        case 200..<300: return
        case 401:
            // The Worker no longer takes this token (its secret changed, or it
            // expired between the check and the request). Dropping it makes
            // the app ask for a sign-in instead of failing every sync.
            if fixedSession == nil, keychain.service == SessionKeychain.standard.service {
                keychain.delete()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .oneDaySessionEnded, object: nil)
                }
            }
            throw Failure.notSignedIn
        case 403: throw Failure.forbidden
        case 404: throw Failure.notFound
        case 409: throw Failure.conflict
        case 429, 500..<600: throw Failure.unavailable
        default: throw Failure.badResponse(status)
        }
    }

    // MARK: Session

    /// The token to send, refreshed first when it's close to running out.
    /// A refresh that fails keeps the old token: it's still good.
    func token() async throws -> String {
        if let fixedSession { return fixedSession.token }
        guard let saved = keychain.load(), saved.expiresAt > .now else { throw Failure.notSignedIn }
        guard saved.expiresAt.timeIntervalSinceNow < Self.refreshWindow else { return saved.token }
        return await SessionRefresher.shared.refresh(saved, api: self)?.token ?? saved.token
    }

    fileprivate func requestRefresh(_ saved: AuthService.Session) async -> AuthService.Session? {
        var request = URLRequest(url: url(["auth", "refresh"]), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(saved.token)", forHTTPHeaderField: "authorization")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        struct Body: Decodable { let token: String; let userId: String; let expiresAt: TimeInterval }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              body.userId == saved.userId
        else { return nil }
        let fresh = AuthService.Session(
            token: body.token, userId: body.userId,
            expiresAt: Date(timeIntervalSince1970: body.expiresAt))
        // Signed out, or in as someone else, while this was out.
        guard keychain.load()?.userId == saved.userId else { return nil }
        keychain.save(fresh)
        return fresh
    }
}

/// One refresh at a time: a room sync fires a dozen requests at once, and
/// each would otherwise swap the token.
private actor SessionRefresher {
    static let shared = SessionRefresher()
    private var running: Task<AuthService.Session?, Never>?

    func refresh(_ saved: AuthService.Session, api: OneDayAPI) async -> AuthService.Session? {
        if let running { return await running.value }
        let task = Task { await api.requestRefresh(saved) }
        running = task
        let result = await task.value
        running = nil
        return result
    }
}

extension Notification.Name {
    /// The Worker turned the session down; whoever was signed in has to sign
    /// in again. Posted on the main queue.
    static let oneDaySessionEnded = Notification.Name("oneDaySessionEnded")
}

/// Times on the wire are milliseconds since 1970, as the Worker stores them.
extension Date {
    var apiMillis: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
    init(apiMillis: Int64) { self.init(timeIntervalSince1970: TimeInterval(apiMillis) / 1000) }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
