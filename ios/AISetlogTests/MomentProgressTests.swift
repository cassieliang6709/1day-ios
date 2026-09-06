import XCTest
@testable import AISetlog

/// The camera's progress bars. They used to be three hard-coded capsules with
/// the middle one lit — the same picture for a two-moment story and a
/// fifteen-moment one, and the same picture on the first take and the last.
/// These are the rules that replaced it: draw one segment per moment, light the
/// one you're on, and draw nothing at all rather than something decorative.
final class MomentProgressTests: XCTestCase {

    // MARK: - How many segments, and which one is lit

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

    /// The bug in the old bars, stated as a test: the third moment of five and
    /// the first moment of three must not draw the same thing.
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

    // MARK: - When there is nothing honest to draw

    func testFreeFormCaptureGetsNoIndicator() {
        // The camera tab passes day 1 and no story. Nothing about that is a
        // position, so nothing should be drawn.
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

    // MARK: - What VoiceOver reads

    func testPositionCountsFromOneForTheSpokenLabel() {
        XCTAssertEqual(MomentProgress(day: 3, momentCount: 5)?.position, 3)
        XCTAssertEqual(MomentProgress(day: 1, momentCount: 5)?.position, 1)
    }
}
