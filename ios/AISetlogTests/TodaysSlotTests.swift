import XCTest

@testable import AISetlog

/// Which moment the home card's button opens. Today's, not the earliest empty.
final class TodaysSlotTests: XCTestCase {
    private func progress(total: Int, filled: Set<Int>) -> RoomProgress {
        RoomProgress(
            momentCount: total,
            clips: filled.map {
                DayClip(day: $0, url: URL(fileURLWithPath: "/dev/null"), authorID: "me")
            },
            myID: "me")
    }

    // MARK: - Seven-day stories, where a slot is a day

    /// The bug this exists for: Tuesday missed, Thursday open, and the button
    /// sent you back to Tuesday.
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

    /// Once today is filmed the button has to point somewhere useful, and
    /// re-filming today is not it — so the earliest gap comes back, and the
    /// label is told to say which day that is.
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

    // MARK: - One-day stories, where every slot is today

    /// Passing `nil` keeps the old rule, which is the right one here: three
    /// moments of one day are not three days, so "the earliest empty" is what
    /// "what's next" means.
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
