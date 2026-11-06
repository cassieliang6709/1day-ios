import Foundation
import Security

/// Trades an Apple or Google identity token for 1Day's own session token at
/// the Cloudflare Worker in `workers/api`, and keeps that token in the keychain.
///
/// Every room request sends that token (`OneDayAPI`); without it nothing
/// shared works.
struct AuthService {
    enum Provider: String {
        case apple, google
    }

    struct Session: Codable, Equatable {
        let token: String
        /// `apple:<sub>` or `google:<sub>`, as the Worker issued it.
        let userId: String
        let expiresAt: Date
    }

    enum Failure: Error, Equatable {
        /// The Worker looked at the token and said no (401). Retrying with the
        /// same token won't change that.
        case rejected
        /// No network, timed out, the Worker is down or misconfigured.
        case unavailable
    }

    /// Own domain, not *.workers.dev: that one is blocked in mainland China.
    static let defaultBaseURL = URL(string: "https://auth.liangyue.site")!
    static let timeout: TimeInterval = 10

    var session: URLSession = .shared
    var baseURL: URL = AuthService.defaultBaseURL

    func exchange(_ identityToken: String, from provider: Provider) async throws -> Session {
        var request = URLRequest(
            url: baseURL.appending(path: "auth/\(provider.rawValue)"),
            timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(["identityToken": identityToken])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.unavailable
        }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:
            break
        case 401:
            throw Failure.rejected
        default:
            throw Failure.unavailable
        }

        struct Body: Decodable {
            let token: String
            let userId: String
            let expiresAt: TimeInterval
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              !body.token.isEmpty, !body.userId.isEmpty
        else { throw Failure.unavailable }
        return Session(
            token: body.token,
            userId: body.userId,
            expiresAt: Date(timeIntervalSince1970: body.expiresAt))
    }
}

/// The session token is a login: keychain, not UserDefaults. One item,
/// replaced on every sign-in, removed on sign-out.
struct SessionKeychain {
    static let standard = SessionKeychain(service: "com.cassie.oneday.session")

    let service: String
    private let account = "session"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(_ session: AuthService.Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        delete()
        var item = query
        item[kSecValueData as String] = data
        // Readable in the background (a push waking the app to sync), never
        // copied to another device by a backup restore.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    func load() -> AuthService.Session? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(AuthService.Session.self, from: data)
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
