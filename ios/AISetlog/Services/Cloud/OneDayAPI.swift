import Foundation

struct OneDayAPI {
    enum Failure: Error, Equatable {
        case notSignedIn
        case notFound
        case conflict
        case forbidden
        case unavailable
        case badResponse(Int)
    }

    static var shared = OneDayAPI()

    var baseURL: URL = AuthService.defaultBaseURL
    var session: URLSession = .shared
    var keychain: SessionKeychain = .standard
    var fixedSession: AuthService.Session? = nil
    var timeout: TimeInterval = 30
    var uploadTimeout: TimeInterval = 120

    static let refreshWindow: TimeInterval = 14 * 24 * 60 * 60

    var isSignedIn: Bool {
        guard let saved = keychain.load() else { return false }
        return saved.expiresAt > .now
    }

    static func authorID(forSessionUser userId: String) -> String {
        userId.hasPrefix("apple:") ? String(userId.dropFirst("apple:".count)) : userId
    }


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

    func download(key: String, to destination: URL) async throws {
        var request = URLRequest(
            url: url(["media"] + key.split(separator: "/").map(String.init)),
            timeoutInterval: uploadTimeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "authorization")
        let started = Date()
        let (temp, response): (URL, URLResponse)
        do {
            (temp, response) = try await session.download(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logFailure(request, started: started, error: error)
            throw Failure.unavailable
        }
        Self.logResponse(request, response, started: started, bytes: nil)
        defer { try? FileManager.default.removeItem(at: temp) }
        try check(response)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RoomClipCache.install(temp, to: destination, consumingSource: true)
    }

    private func perform(_ request: URLRequest, uploading file: URL? = nil) async throws -> Data {
        var request = request
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "authorization")
        let started = Date()
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
            Self.logFailure(request, started: started, error: error)
            throw Failure.unavailable
        }
        Self.logResponse(request, response, started: started, bytes: data.count)
        try check(response)
        return data
    }

    private static func logResponse(
        _ request: URLRequest, _ response: URLResponse, started: Date, bytes: Int?
    ) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "?"
        let size = bytes.map { " \($0)B" } ?? ""
        if (200..<300).contains(status) {
            Log.api.info("\(method, privacy: .public) \(path, privacy: .public) \(status) \(ms)ms\(size, privacy: .public)")
        } else {
            Log.api.error("\(method, privacy: .public) \(path, privacy: .public) \(status) \(ms)ms\(size, privacy: .public)")
        }
    }

    private static func logFailure(_ request: URLRequest, started: Date, error: any Error) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "?"
        Log.api.error("\(method, privacy: .public) \(path, privacy: .public) failed \(ms)ms: \(error.localizedDescription, privacy: .public)")
    }

    private func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.unavailable }
        switch status {
        case 200..<300: return
        case 401:
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
        guard keychain.load()?.userId == saved.userId else { return nil }
        keychain.save(fresh)
        return fresh
    }
}

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
    static let oneDaySessionEnded = Notification.Name("oneDaySessionEnded")
}

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
