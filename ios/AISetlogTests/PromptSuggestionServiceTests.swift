import XCTest
@testable import AISetlog

/// One sentence in, prompts out — and, more importantly, what happens on every
/// path where that doesn't work. The feature is an accelerator, so every
/// failure has to land the user back in front of the list they can fill in
/// themselves, with nothing of theirs disturbed.
final class PromptSuggestionServiceTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        StubURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    private func service() -> RemotePromptSuggestionService {
        RemotePromptSuggestionService(
            session: session,
            endpoint: URL(string: "https://example.test/api/suggest-prompts")!,
            deviceID: "test-device")
    }

    // MARK: - Parsing

    func testAWellFormedResponseParsesIntoPrompts() throws {
        let data = Data(#"{"prompts":["出门前","第一个箱子","新家的灯"]}"#.utf8)

        let prompts = try RemotePromptSuggestionService.prompts(from: data, wanted: 7)

        XCTAssertEqual(prompts, ["出门前", "第一个箱子", "新家的灯"])
    }

    func testMalformedJSONThrowsRatherThanCrashing() {
        for body in ["not json at all", "{}", #"{"prompts":"一个箱子"}"#, ""] {
            XCTAssertThrowsError(
                try RemotePromptSuggestionService.prompts(from: Data(body.utf8), wanted: 7),
                body)
        }
    }

    /// Two is what the composer needs to make a story. One isn't a shorter
    /// answer, it's a broken one.
    func testTooFewPromptsCountsAsMalformed() {
        let data = Data(#"{"prompts":["就一个"]}"#.utf8)

        XCTAssertThrowsError(
            try RemotePromptSuggestionService.prompts(from: data, wanted: 7)
        ) { error in
            XCTAssertEqual(error as? PromptSuggestionError, .malformed)
        }
    }

    func testBlankAndPaddedPromptsAreCleanedUp() throws {
        let data = Data(#"{"prompts":["  出门前 ","","   ","第一个箱子"]}"#.utf8)

        let prompts = try RemotePromptSuggestionService.prompts(from: data, wanted: 7)

        XCTAssertEqual(prompts, ["出门前", "第一个箱子"])
    }

    func testMorePromptsThanAskedForAreTrimmed() throws {
        let data = Data(#"{"prompts":["一","二","三","四","五"]}"#.utf8)

        let prompts = try RemotePromptSuggestionService.prompts(from: data, wanted: 3)

        XCTAssertEqual(prompts, ["一", "二", "三"])
    }

    // MARK: - The round trip

    func testASuccessfulCallReturnsPrompts() async throws {
        StubURLProtocol.respond(status: 200, body: #"{"prompts":["出门前","第一个箱子"]}"#)

        let prompts = try await service().suggest(
            intent: "今天要搬家", count: 7, language: .chinese)

        XCTAssertEqual(prompts, ["出门前", "第一个箱子"])
    }

    func testTheSentenceAndLanguageActuallyReachTheServer() async throws {
        StubURLProtocol.respond(status: 200, body: #"{"prompts":["a","b"]}"#)

        _ = try await service().suggest(intent: "今天要搬家", count: 5, language: .english)

        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let sent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["intent"] as? String, "今天要搬家")
        XCTAssertEqual(sent["count"] as? Int, 5)
        XCTAssertEqual(sent["language"] as? String, "en")
        XCTAssertEqual(sent["device"] as? String, "test-device")
    }

    /// No network is the ordinary case, not an exceptional one: people make
    /// stories on the subway.
    func testATransportFailureIsJustUnavailable() async {
        StubURLProtocol.fail(with: URLError(.notConnectedToInternet))

        await assertThrows(.unavailable) {
            try await self.service().suggest(intent: "今天要搬家", count: 7, language: .chinese)
        }
    }

    func testATimeoutIsTreatedAsAFailureRatherThanHanging() async {
        StubURLProtocol.fail(with: URLError(.timedOut))

        await assertThrows(.unavailable) {
            try await self.service().suggest(intent: "今天要搬家", count: 7, language: .chinese)
        }
    }

    func testRateLimitingIsDistinguishableFromEverythingElse() async {
        StubURLProtocol.respond(status: 429, body: #"{"error":"rate_limited"}"#)

        await assertThrows(.rateLimited) {
            try await self.service().suggest(intent: "今天要搬家", count: 7, language: .chinese)
        }
    }

    func testAServerErrorIsUnavailable() async {
        StubURLProtocol.respond(status: 502, body: #"{"error":"unavailable"}"#)

        await assertThrows(.unavailable) {
            try await self.service().suggest(intent: "今天要搬家", count: 7, language: .chinese)
        }
    }

    /// A 200 carrying nonsense is the one the app is most likely to meet, since
    /// what's upstream is a model writing text.
    func testAGoodStatusWithABadBodyIsMalformed() async {
        StubURLProtocol.respond(status: 200, body: "<html>gateway</html>")

        await assertThrows(.malformed) {
            try await self.service().suggest(intent: "今天要搬家", count: 7, language: .chinese)
        }
    }

    // MARK: - The install id

    func testTheInstallIDIsMintedOnceAndKept() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "install-id-tests"))
        defaults.removePersistentDomain(forName: "install-id-tests")

        let first = DeviceIdentity.installID(in: defaults)
        let second = DeviceIdentity.installID(in: defaults)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        defaults.removePersistentDomain(forName: "install-id-tests")
    }

    private func assertThrows(
        _ expected: PromptSuggestionError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> [String]
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? PromptSuggestionError, expected, file: file, line: line)
        }
    }
}

/// Stands in for the network so the failure paths are reachable in a test.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var error: Error?
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
        lastBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `httpBody` is stripped by the loading system, so read it back out of
        // the stream the way a real transport would.
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.drain)

        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status,
            httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
