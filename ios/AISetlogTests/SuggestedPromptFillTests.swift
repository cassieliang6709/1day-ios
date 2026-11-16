import XCTest
@testable import AISetlog

final class SuggestedPromptFillTests: XCTestCase {
    func testBlankRowsGetFilledInOrder() {
        let filled = SuggestedPromptFill.apply(["一", "二"], to: ["", ""])

        XCTAssertEqual(filled, ["一", "二"])
    }

    func testWhatTheUserAlreadyWroteIsLeftAlone() {
        let filled = SuggestedPromptFill.apply(["一", "二"], to: ["我的题目", ""])

        XCTAssertEqual(filled, ["我的题目", "一", "二"])
    }

    func testLeftoverSuggestionsAreAppendedUpToTheLimit() {
        let filled = SuggestedPromptFill.apply(
            ["一", "二", "三", "四"], to: ["我的题目", ""], limit: 3)

        XCTAssertEqual(filled, ["我的题目", "一", "二"])
    }

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
        let full = (1...StoryMoments.maxCount).map(String.init)

        XCTAssertEqual(SuggestedPromptFill.apply(["新的"], to: full), full)
    }

    func testAnotherSetReplacesRowsThatStillReadAsOffered() {
        let offered = ["一", "二", "三"]
        let filled = SuggestedPromptFill.apply(
            ["甲", "乙", "丙"], to: offered, replacing: offered)

        XCTAssertEqual(filled, ["甲", "乙", "丙"])
    }

    func testAnotherSetKeepsRowsTheUserEdited() {
        let offered = ["一", "二", "三"]
        let filled = SuggestedPromptFill.apply(
            ["甲", "乙", "丙"], to: ["一", "我改过的二", "三"], replacing: offered)

        XCTAssertEqual(filled, ["甲", "我改过的二", "乙", "丙"])
    }

    func testUnreplacedOfferedRowsAreDropped() {
        let offered = ["一", "二", "三"]
        let filled = SuggestedPromptFill.apply(
            ["甲"], to: ["一", "我的", "二", "三"], replacing: offered)

        XCTAssertEqual(filled, ["甲", "我的"])
    }

    func testAnotherSetStillRespectsTheLimit() {
        let offered = ["一", "二"]
        let filled = SuggestedPromptFill.apply(
            ["甲", "乙", "丙", "丁"], to: ["一", "我的", "二"], replacing: offered, limit: 3)

        XCTAssertEqual(filled, ["甲", "我的", "乙"])
    }

    func testCanReplaceOnlyWhileAnOfferedRowIsUntouched() {
        let offered = ["一", "二"]

        XCTAssertFalse(SuggestedPromptFill.canReplace(["", ""], offered: []))
        XCTAssertTrue(SuggestedPromptFill.canReplace(["一", "我的"], offered: offered))
        XCTAssertTrue(SuggestedPromptFill.canReplace([" 二 "], offered: offered))
        XCTAssertFalse(SuggestedPromptFill.canReplace(["我的", "也是我的"], offered: offered))
    }
}
