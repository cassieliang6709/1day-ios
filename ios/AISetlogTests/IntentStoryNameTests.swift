import XCTest
@testable import AISetlog

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

    func testASentenceTooLongToBeATitleIsNotUsed() {
        let long = String(repeating: "搬", count: IntentStoryName.lengthLimit + 1)
        XCTAssertNil(IntentStoryName.derive(from: long))

        let atTheLimit = String(repeating: "搬", count: IntentStoryName.lengthLimit)
        XCTAssertEqual(IntentStoryName.derive(from: atTheLimit), atTheLimit)
    }
}
