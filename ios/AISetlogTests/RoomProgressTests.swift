import XCTest
@testable import AISetlog

/// The header's numbers. A shared room used to report only my own cards, so a
/// room three friends had been filming in all morning read "0/5" to whoever
/// hadn't filmed yet.
final class RoomProgressTests: XCTestCase {
    private let me = "me"

    private func clip(day: Int, author: String?) -> DayClip {
        DayClip(
            day: day,
            url: URL(fileURLWithPath: "/tmp/\(author ?? "none")-\(day).mp4"),
            authorID: author)
    }

    func testAnEmptyStoryIsZeroOfItsMoments() {
        let progress = RoomProgress(momentCount: 5, clips: [], myID: me)

        XCTAssertEqual(progress.filled, 0)
        XCTAssertEqual(progress.mine, 0)
        XCTAssertEqual(progress.clipCount, 0)
        XCTAssertFalse(progress.hasOthers)
    }

    func testASoloStoryCountsMyCards() {
        let progress = RoomProgress(
            momentCount: 3,
            clips: [clip(day: 1, author: "local"), clip(day: 2, author: "local")],
            myID: me)

        XCTAssertEqual(progress.filled, 2)
        XCTAssertEqual(progress.mine, 2)
        XCTAssertFalse(progress.hasOthers, "nobody else is in a solo story")
    }

    /// The bug, in one assertion: three moments have been filmed and none of
    /// them are mine.
    func testFriendsClipsCountTowardTheDay() {
        let progress = RoomProgress(
            momentCount: 5,
            clips: [
                clip(day: 1, author: "ana"),
                clip(day: 2, author: "milo"),
                clip(day: 3, author: "ana"),
            ],
            myID: me)

        XCTAssertEqual(progress.filled, 3)
        XCTAssertEqual(progress.mine, 0)
        XCTAssertTrue(progress.hasOthers)
    }

    /// Two people on the same moment is one moment, and two clips: the day
    /// hasn't got further along, but the film got longer.
    func testTwoTakesOfOneMomentIsStillOneMoment() {
        let progress = RoomProgress(
            momentCount: 5,
            clips: [clip(day: 1, author: "ana"), clip(day: 1, author: me)],
            myID: me)

        XCTAssertEqual(progress.filled, 1)
        XCTAssertEqual(progress.mine, 1)
        XCTAssertEqual(progress.clipCount, 2)
        XCTAssertFalse(progress.hasOthers, "same moment — the counts agree")
    }

    /// The home card used to say "Next: Morning light" while Morning light was
    /// on the screen below it, filmed by a friend an hour earlier.
    func testTheNextMomentIsTheOneNobodyHasFilmed() {
        let progress = RoomProgress(
            momentCount: 5,
            clips: [
                clip(day: 1, author: "ana"),
                clip(day: 2, author: "milo"),
                clip(day: 3, author: "ana"),
            ],
            myID: me)

        XCTAssertEqual(progress.nextOpenMoment, 4)
    }

    /// Gaps count. Filming the last moment first shouldn't send everyone past
    /// the four that are still empty.
    func testItPointsAtTheFirstGapNotThePileEnd() {
        let progress = RoomProgress(
            momentCount: 5, clips: [clip(day: 5, author: "ana")], myID: me)

        XCTAssertEqual(progress.nextOpenMoment, 1)
        XCTAssertFalse(progress.isComplete)
    }

    /// In a room the day finishes when the day finishes, not when I do.
    func testTheDayIsCompleteWhenEveryMomentIsIn() {
        let progress = RoomProgress(
            momentCount: 3,
            clips: [
                clip(day: 1, author: "ana"),
                clip(day: 2, author: "milo"),
                clip(day: 3, author: me),
            ],
            myID: me)

        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.nextOpenMoment, 3, "nowhere left to point but the end")
    }

    func testAnEmptyStoryIsNotComplete() {
        XCTAssertFalse(RoomProgress(momentCount: 0, clips: [], myID: me).isComplete)
        XCTAssertEqual(RoomProgress(momentCount: 0, clips: [], myID: me).nextOpenMoment, 1)
    }

    /// A room can outlive an edit that shortened the prompt list. Reporting
    /// "6/5" would be a bug report about arithmetic instead of about editing.
    func testItNeverClaimsMoreMomentsThanExist() {
        let progress = RoomProgress(
            momentCount: 2,
            clips: (1...6).map { clip(day: $0, author: "ana") },
            myID: me)

        XCTAssertEqual(progress.filled, 2)
        XCTAssertEqual(progress.clipCount, 6)
    }

    /// Clamping instead of excluding would have called this "2/2, watch your
    /// film" while both real moments sat empty — a number that is wrong, not
    /// merely stale.
    func testClipsPastTheEndDontFillTheMomentsBeforeThem() {
        let progress = RoomProgress(
            momentCount: 2,
            clips: [clip(day: 3, author: "ana"), clip(day: 4, author: "ana")],
            myID: me)

        XCTAssertEqual(progress.filled, 0)
        XCTAssertFalse(progress.isComplete)
        XCTAssertEqual(progress.nextOpenMoment, 1)
        XCTAssertEqual(progress.clipCount, 2, "they still exist, they just don't count")
    }

    /// A clip with no author is somebody's, but not demonstrably mine.
    func testAnAuthorlessClipCountsForTheDayButNotForMe() {
        let progress = RoomProgress(
            momentCount: 3, clips: [clip(day: 1, author: nil)], myID: me)

        XCTAssertEqual(progress.filled, 1)
        XCTAssertEqual(progress.mine, 0)
    }

    /// Signing out changes who I am. The room cache is cleared with it now, so
    /// this is the shape of the bug rather than a live path — but if the two
    /// ever drift apart again, my own takes get credited to a stranger.
    func testMyOwnClipsArentMineUnderADifferentIdentity() {
        let clips = [clip(day: 1, author: "apple-id-123")]

        XCTAssertEqual(RoomProgress(momentCount: 3, clips: clips, myID: "apple-id-123").mine, 1)
        XCTAssertEqual(
            RoomProgress(momentCount: 3, clips: clips, myID: RoomProgress.soloAuthorID).mine, 0)
    }
}
