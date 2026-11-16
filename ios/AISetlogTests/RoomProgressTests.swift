import XCTest
@testable import AISetlog

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

    func testItPointsAtTheFirstGapNotThePileEnd() {
        let progress = RoomProgress(
            momentCount: 5, clips: [clip(day: 5, author: "ana")], myID: me)

        XCTAssertEqual(progress.nextOpenMoment, 1)
        XCTAssertFalse(progress.isComplete)
    }

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

    func testItNeverClaimsMoreMomentsThanExist() {
        let progress = RoomProgress(
            momentCount: 2,
            clips: (1...6).map { clip(day: $0, author: "ana") },
            myID: me)

        XCTAssertEqual(progress.filled, 2)
        XCTAssertEqual(progress.clipCount, 6)
    }

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

    func testAnAuthorlessClipCountsForTheDayButNotForMe() {
        let progress = RoomProgress(
            momentCount: 3, clips: [clip(day: 1, author: nil)], myID: me)

        XCTAssertEqual(progress.filled, 1)
        XCTAssertEqual(progress.mine, 0)
    }

    func testMyOwnClipsArentMineUnderADifferentIdentity() {
        let clips = [clip(day: 1, author: "apple-id-123")]

        XCTAssertEqual(RoomProgress(momentCount: 3, clips: clips, myID: "apple-id-123").mine, 1)
        XCTAssertEqual(
            RoomProgress(momentCount: 3, clips: clips, myID: RoomProgress.soloAuthorID).mine, 0)
    }
}
