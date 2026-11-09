import XCTest
@testable import AISetlog

/// Trading an Apple or Google token for 1Day's own session at
/// `workers/api`. The Worker's side (what it accepts and rejects) is tested
/// in `workers/api/test`; these cover what the app sends and how it reads
/// every kind of answer.
final class AuthServiceTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthStubProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        AuthStubProtocol.reset()
        SessionKeychain(service: Self.testService).delete()
        session = nil
        super.tearDown()
    }

    private static let testService = "com.cassie.oneday.session.tests"

    private func service() -> AuthService {
        AuthService(session: session, baseURL: URL(string: "https://example.test")!)
    }

    // MARK: - The request

    func testItPostsTheTokenToTheProvidersPath() async throws {
        AuthStubProtocol.respond(
            status: 200,
            body: #"{"token":"t","userId":"apple:001","expiresAt":1800000000}"#)

        _ = try await service().exchange("identity-token", from: .apple)

        XCTAssertEqual(AuthStubProtocol.lastURL?.absoluteString, "https://example.test/auth/apple")
        XCTAssertEqual(AuthStubProtocol.lastMethod, "POST")
        let sent = try JSONDecoder().decode(
            [String: String].self, from: XCTUnwrap(AuthStubProtocol.lastBody))
        XCTAssertEqual(sent, ["identityToken": "identity-token"])
    }

    func testGoogleGoesToItsOwnPath() async throws {
        AuthStubProtocol.respond(
            status: 200,
            body: #"{"token":"t","userId":"google:9","expiresAt":1800000000}"#)

        _ = try await service().exchange("x", from: .google)

        XCTAssertEqual(AuthStubProtocol.lastURL?.path, "/auth/google")
    }

    // MARK: - The answer

    func testASuccessfulAnswerBecomesASession() async throws {
        AuthStubProtocol.respond(
            status: 200,
            body: #"{"token":"abc.def.ghi","userId":"apple:001","expiresAt":1800000000}"#)

        let result = try await service().exchange("x", from: .apple)

        XCTAssertEqual(result, AuthService.Session(
            token: "abc.def.ghi",
            userId: "apple:001",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    func testA401MeansRejected() async {
        AuthStubProtocol.respond(status: 401, body: #"{"error":"invalid_token"}"#)
        await assertThrows(.rejected) { try await self.service().exchange("x", from: .apple) }
    }

    func testServerTroubleIsUnavailable() async {
        for status in [400, 404, 500, 502, 503] {
            AuthStubProtocol.respond(status: status, body: #"{"error":"unavailable"}"#)
            await assertThrows(.unavailable) { try await self.service().exchange("x", from: .apple) }
        }
    }

    func testNoNetworkIsUnavailable() async {
        AuthStubProtocol.fail(with: URLError(.notConnectedToInternet))
        await assertThrows(.unavailable) { try await self.service().exchange("x", from: .apple) }
    }

    /// A 200 that isn't a session (a captive portal, a misrouted domain) must
    /// not be stored as one.
    func testA200WithoutASessionIsUnavailable() async {
        for body in ["<html>hotel wifi</html>", #"{"token":"","userId":"apple:1","expiresAt":1}"#, "{}"] {
            AuthStubProtocol.respond(status: 200, body: body)
            await assertThrows(.unavailable) { try await self.service().exchange("x", from: .apple) }
        }
    }

    // MARK: - Keychain

    func testTheSessionSurvivesAndCanBeRemoved() throws {
        // An unsigned test host (CI runs with CODE_SIGNING_ALLOWED=NO) has no
        // keychain entitlement, so SecItemAdd fails silently and load() is nil.
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.testService + ".probe",
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data([0]),
        ]
        let status = SecItemAdd(probe as CFDictionary, nil)
        SecItemDelete(probe as CFDictionary)
        try XCTSkipUnless(status == errSecSuccess, "keychain unavailable in this test host (status \(status))")

        let keychain = SessionKeychain(service: Self.testService)
        let first = AuthService.Session(token: "one", userId: "apple:1", expiresAt: Date(timeIntervalSince1970: 1))
        let second = AuthService.Session(token: "two", userId: "google:2", expiresAt: Date(timeIntervalSince1970: 2))

        XCTAssertNil(keychain.load())
        keychain.save(first)
        XCTAssertEqual(keychain.load(), first)
        // Signing in again replaces it rather than failing on a duplicate.
        keychain.save(second)
        XCTAssertEqual(keychain.load(), second)
        keychain.delete()
        XCTAssertNil(keychain.load())
    }

    // MARK: -

    private func assertThrows(
        _ expected: AuthService.Failure,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> some Any
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AuthService.Failure, expected, file: file, line: line)
        }
    }
}

/// Stands in for the Worker.
private final class AuthStubProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var error: Error?
    nonisolated(unsafe) static var lastURL: URL?
    nonisolated(unsafe) static var lastMethod: String?
    nonisolated(unsafe) static var lastBody: Data?

    static func respond(status: Int, body: String) {
        reset()
        self.status = status
        self.body = Data(body.utf8)
    }

    static func fail(with error: Error) {
        reset()
        self.error = error
    }

    static func reset() {
        status = 200
        body = Data()
        error = nil
        lastURL = nil
        lastMethod = nil
        lastBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastURL = request.url
        Self.lastMethod = request.httpMethod
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.drain)
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
