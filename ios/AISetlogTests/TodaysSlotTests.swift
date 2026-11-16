import XCTest

@testable import AISetlog

final class TodaysSlotTests: XCTestCase {
    private func progress(total: Int, filled: Set<Int>) -> RoomProgress {
        RoomProgress(
            momentCount: total,
            clips: filled.map {
                DayClip(day: $0, url: URL(fileURLWithPath: "/dev/null"), authorID: "me")
            },
            myID: "me")
    }


    func testAMissedDayDoesNotHijackTodaysButton() {
        let p = progress(total: 7, filled: [1, 3])
        XCTAssertEqual(p.nextOpenMoment, 2, "the old rule")
        XCTAssertEqual(p.slotToOffer(today: 4), 4)
        XCTAssertTrue(p.offeringToday(today: 4))
    }

    func testTodayIsOfferedEvenWhenItIsTheOnlyEmptyOne() {
        let p = progress(total: 7, filled: [1, 2, 3, 5, 6, 7])
        XCTAssertEqual(p.slotToOffer(today: 4), 4)
    }

    func testOnceTodayIsFilmedTheEarliestGapComesBack() {
        let p = progress(total: 7, filled: [1, 4])
        XCTAssertEqual(p.slotToOffer(today: 4), 2)
        XCTAssertFalse(p.offeringToday(today: 4))
    }

    func testADayPastTheEndClampsToTheLastOne() {
        let p = progress(total: 7, filled: [])
        XCTAssertEqual(p.slotToOffer(today: 12), 7)
    }

    func testDayZeroOrNegativeClampsToTheFirst() {
        let p = progress(total: 7, filled: [])
        XCTAssertEqual(p.slotToOffer(today: 0), 1)
        XCTAssertEqual(p.slotToOffer(today: -3), 1)
    }

    func testAFullStoryStillHasSomewhereToPoint() {
        let p = progress(total: 3, filled: [1, 2, 3])
        XCTAssertEqual(p.slotToOffer(today: 2), 3)
    }


    func testAOneDayStoryUsesTheEarliestEmptyMoment() {
        let p = progress(total: 3, filled: [1])
        XCTAssertEqual(p.slotToOffer(today: nil), 2)
        XCTAssertTrue(p.offeringToday(today: nil))
    }

    func testAnEmptyStoryOffersTheFirstSlot() {
        let p = progress(total: 0, filled: [])
        XCTAssertEqual(p.slotToOffer(today: 3), 1)
        XCTAssertEqual(p.slotToOffer(today: nil), 1)
    }
}
