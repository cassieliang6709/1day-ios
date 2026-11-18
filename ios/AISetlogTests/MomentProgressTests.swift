import XCTest
@testable import AISetlog

final class MomentProgressTests: XCTestCase {


    func testOneSegmentPerMomentInTheStory() {
        XCTAssertEqual(MomentProgress(day: 1, momentCount: 5)?.count, 5)
        XCTAssertEqual(MomentProgress(day: 1, momentCount: 2)?.count, 2)
        XCTAssertEqual(MomentProgress(day: 9, momentCount: 15)?.count, 15)
    }

    func testTheLitSegmentFollowsTheMomentYoureFilming() {
        XCTAssertEqual(MomentProgress(day: 1, momentCount: 5)?.activeIndex, 0)
        XCTAssertEqual(MomentProgress(day: 3, momentCount: 5)?.activeIndex, 2)
        XCTAssertEqual(MomentProgress(day: 5, momentCount: 5)?.activeIndex, 4)
    }

    func testDifferentPlacesInDifferentStoriesDrawDifferently() {
        let thirdOfFive = MomentProgress(day: 3, momentCount: 5)
        let firstOfThree = MomentProgress(day: 1, momentCount: 3)
        XCTAssertNotEqual(thirdOfFive, firstOfThree)
    }

    func testExactlyOneSegmentIsLit() {
        guard let progress = MomentProgress(day: 4, momentCount: 6) else {
            return XCTFail("a fourth moment of six is a real place to be")
        }
        let lit = (0..<progress.count).filter { progress.isActive($0) }
        XCTAssertEqual(lit, [3])
    }


    func testFreeFormCaptureGetsNoIndicator() {
        XCTAssertNil(MomentProgress(day: 1, momentCount: 0))
    }

    func testAOneMomentStoryGetsNoIndicator() {
        XCTAssertNil(MomentProgress(day: 1, momentCount: 1))
    }

    func testADayOutsideTheStoryGetsNoIndicator() {
        XCTAssertNil(MomentProgress(day: 0, momentCount: 3))
        XCTAssertNil(MomentProgress(day: 4, momentCount: 3))
        XCTAssertNil(MomentProgress(day: -2, momentCount: 3))
    }

    func testANegativeCountGetsNoIndicator() {
        XCTAssertNil(MomentProgress(day: 1, momentCount: -3))
    }


    func testPositionCountsFromOneForTheSpokenLabel() {
        XCTAssertEqual(MomentProgress(day: 3, momentCount: 5)?.position, 3)
        XCTAssertEqual(MomentProgress(day: 1, momentCount: 5)?.position, 1)
    }
}
