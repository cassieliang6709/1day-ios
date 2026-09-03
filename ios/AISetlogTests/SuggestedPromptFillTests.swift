import XCTest
@testable import AISetlog

/// What the user typed wins. A generator that overwrites the sentence you just
/// wrote is worse than no generator, because you can't hand it the next one.
final class SuggestedPromptFillTests: XCTestCase {
    func testBlankRowsGetFilledInOrder() {
        let filled = SuggestedPromptFill.apply(["一", "二"], to: ["", ""])

        XCTAssertEqual(filled, ["一", "二"])
    }

    /// The user's row stays put and stays first; the suggestions go around it.
    func testWhatTheUserAlreadyWroteIsLeftAlone() {
        let filled = SuggestedPromptFill.apply(["一", "二"], to: ["我的题目", ""])

        XCTAssertEqual(filled, ["我的题目", "一", "二"])
    }

    func testLeftoverSuggestionsAreAppendedUpToTheLimit() {
        let filled = SuggestedPromptFill.apply(
            ["一", "二", "三", "四"], to: ["我的题目", ""], limit: 3)

        XCTAssertEqual(filled, ["我的题目", "一", "二"])
    }

    /// A failed generation calls this with nothing, and nothing is exactly what
    /// it should do to a half-filled list.
    func testNoSuggestionsLeavesTheListExactlyAsItWas() {
        let answers = ["我的题目", "", "另一个"]

        XCTAssertEqual(SuggestedPromptFill.apply([], to: answers), answers)
        XCTAssertEqual(SuggestedPromptFill.apply(["", "   "], to: answers), answers)
    }

    func testWhitespaceOnlyRowsCountAsBlank() {
        let filled = SuggestedPromptFill.apply(["一"], to: ["   ", "我的题目"])

        XCTAssertEqual(filled, ["一", "我的题目"])
    }

    func testAFullListIsNotGrownPastTheLimit() {
        let full = ["1", "2", "3", "4", "5", "6", "7"]

        XCTAssertEqual(SuggestedPromptFill.apply(["新的"], to: full), full)
    }
}
