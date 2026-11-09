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
        let full = (1...StoryMoments.maxCount).map(String.init)

        XCTAssertEqual(SuggestedPromptFill.apply(["新的"], to: full), full)
    }

    /// The second tap used to do nothing: every row was full of the first
    /// round, and filling only blanks left nothing to fill. Rows that still
    /// read exactly as offered are swapped for the new set.
    func testAnotherSetReplacesRowsThatStillReadAsOffered() {
        let offered = ["一", "二", "三"]
        let filled = SuggestedPromptFill.apply(
            ["甲", "乙", "丙"], to: offered, replacing: offered)

        XCTAssertEqual(filled, ["甲", "乙", "丙"])
    }

    /// What the user rewrote is theirs now, even though it started life as a
    /// suggestion — only the untouched rows are fair game.
    func testAnotherSetKeepsRowsTheUserEdited() {
        let offered = ["一", "二", "三"]
        let filled = SuggestedPromptFill.apply(
            ["甲", "乙", "丙"], to: ["一", "我改过的二", "三"], replacing: offered)

        XCTAssertEqual(filled, ["甲", "我改过的二", "乙", "丙"])
    }

    /// A shorter new round shouldn't leave half of the old set behind looking
    /// like part of the new one.
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
