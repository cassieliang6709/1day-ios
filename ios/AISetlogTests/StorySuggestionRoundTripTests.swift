import XCTest
@testable import AISetlog

final class StorySuggestionRoundTripTests: XCTestCase {
    func testNewResponseTraversesProtocolAndOldMethodStillReturnsPrompts() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StoryResponseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service: any PromptSuggesting = RemotePromptSuggestionService(
            session: session, endpoint: URL(string: "https://example.test/story")!, deviceID: "isolated-test")
        let result = try await service.suggestStory(intent: "today", count: 3, language: .english)
        XCTAssertEqual(result.title, "Moving day")
        XCTAssertEqual(result.prompts, ["First box", "New door", "Evening light"])
        let legacy = try await service.suggest(intent: "today", count: 3, language: .english)
        XCTAssertEqual(legacy, result.prompts)
    }
}

private final class StoryResponseProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"title":" Moving day ","prompts":["First box","New door","Evening light"]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
