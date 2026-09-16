import XCTest
@testable import AISetlog

final class StorySuggestionTests: XCTestCase {
    func testOptionalTitleKeepsLegacyAndMalformedTitleCompatible() throws {
        for field in ["", #", "title":null"#, #", "title":42"#, #", "title":"   ""#] {
            let data = Data((#"{"prompts":[" a ","b"]"# + field + "}").utf8)
            let result = try RemotePromptSuggestionService.story(from: data, wanted: 7)
            XCTAssertNil(result.title)
            XCTAssertEqual(result.prompts, ["a", "b"])
        }
    }

    func testTitleAndUserLanguageArePreservedWithoutTranslation() throws {
        let data = Data(#"{"title":"  My 搬家日  ","prompts":["我的 coffee","新家"]}"#.utf8)
        let result = try RemotePromptSuggestionService.story(from: data, wanted: 7)
        XCTAssertEqual(result.title, "My 搬家日")
        XCTAssertEqual(result.prompts, ["我的 coffee", "新家"])
        XCTAssertEqual(try RemotePromptSuggestionService.prompts(from: data, wanted: 7), result.prompts)
    }

    func testTitleCannotRescueMalformedPrompts() {
        XCTAssertThrowsError(try RemotePromptSuggestionService.story(
            from: Data(#"{"title":"好标题","prompts":["只有一个"]}"#.utf8), wanted: 7))
    }

    func testLegacyInjectedServiceAdaptsThroughExistential() async throws {
        let service: any PromptSuggesting = LegacySuggestionStub()
        let result = try await service.suggestStory(intent: "today", count: 7, language: .english)
        XCTAssertEqual(result, StorySuggestion(title: nil, prompts: ["a", "b"]))
    }

    func testRegenerationPreservesCurrentEditsAndOnlyFillsBlanks() {
        let current = ["我手写的 English", "", "已经改过的题目"]
        let result = SuggestedPromptFill.apply(["新一", "新二"], to: current)
        XCTAssertEqual(result, [current[0], "新一", current[2], "新二"])
        XCTAssertEqual(SuggestedPromptFill.apply(["替换"], to: Array(repeating: "保留", count: 7)), Array(repeating: "保留", count: 7))
    }
}

private struct LegacySuggestionStub: PromptSuggesting {
    func suggest(intent: String, count: Int, language: AppLanguage) async throws -> [String] { ["a", "b"] }
}
