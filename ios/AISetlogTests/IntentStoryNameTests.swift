import XCTest
@testable import AISetlog

/// The sentence that produced the prompts is usually the story's name too.
/// These tests are mostly about when it *isn't*.
final class IntentStoryNameTests: XCTestCase {
    func testTheSentenceBecomesTheName() {
        XCTAssertEqual(IntentStoryName.derive(from: "今天要搬家"), "今天要搬家")
        XCTAssertEqual(IntentStoryName.derive(from: "moving house today"), "moving house today")
    }

    func testPunctuationAndSpaceAtTheEdgesIsDropped() {
        XCTAssertEqual(IntentStoryName.derive(from: "  今天要搬家。 "), "今天要搬家")
        XCTAssertEqual(IntentStoryName.derive(from: "moving house today!"), "moving house today")
    }

    func testPunctuationInsideTheSentenceStays() {
        XCTAssertEqual(IntentStoryName.derive(from: "搬家，然后吃饭"), "搬家，然后吃饭")
    }

    func testNothingToNameGivesNothing() {
        XCTAssertNil(IntentStoryName.derive(from: ""))
        XCTAssertNil(IntentStoryName.derive(from: "   "))
        XCTAssertNil(IntentStoryName.derive(from: "。。。"))
    }

    /// A paragraph is a sentence, not a title. Leaving the field empty says
    /// "unfinished", which is true; filling it with 60 characters says "named",
    /// which isn't.
    func testASentenceTooLongToBeATitleIsNotUsed() {
        let long = String(repeating: "搬", count: IntentStoryName.lengthLimit + 1)
        XCTAssertNil(IntentStoryName.derive(from: long))

        let atTheLimit = String(repeating: "搬", count: IntentStoryName.lengthLimit)
        XCTAssertEqual(IntentStoryName.derive(from: atTheLimit), atTheLimit)
    }
}
