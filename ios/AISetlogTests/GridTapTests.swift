import XCTest
@testable import AISetlog

/// How the contact sheet stacks a moment several people filmed. Whether that
/// moment is still open to me is `StoryAgendaTests`' question now — a
/// thumbnail plays what's there and nothing else, so it no longer has to
/// decide between watching and filming.
final class GridTapTests: XCTestCase {
    private let myID = "me"
    private let friendID = "friend"

    private func clip(day: Int, authorID: String) -> DayClip {
        DayClip(day: day, url: URL(fileURLWithPath: "/tmp/\(authorID)-\(day).mov"),
                authorName: authorID, authorID: authorID)
    }

    // MARK: - Lanes

    private var roster: [(id: String, name: String)] {
        [(id: friendID, name: "Ada"), (id: myID, name: "Me"), (id: "zoe", name: "Zoe")]
    }

    func testMyFilmedLaneComesFirstAndTheRestFollowByName() {
        let lanes = StoryGridView.lanes(
            slotClips: [
                clip(day: 1, authorID: friendID),
                clip(day: 1, authorID: "zoe"),
                clip(day: 1, authorID: myID),
            ],
            members: roster,
            myID: myID)

        XCTAssertEqual(lanes.map(\.authorID), [myID, friendID, "zoe"])
        XCTAssertTrue(lanes[0].isMine)
        XCTAssertNotNil(lanes[0].clip)
        XCTAssertNotNil(lanes[1].clip, "Ada has")
        XCTAssertNotNil(lanes[2].clip)
    }

    func testRosterMembersWithoutClipsDoNotCreateEmptyLanes() {
        let lanes = StoryGridView.lanes(slotClips: [], members: roster, myID: myID)
        XCTAssertTrue(lanes.isEmpty)
    }

    func testOnlyFilmedFriendsAppearBeforeIRecord() {
        let lanes = StoryGridView.lanes(
            slotClips: [clip(day: 1, authorID: friendID)], members: roster, myID: myID)

        XCTAssertEqual(lanes.map(\.authorID), [friendID])
        XCTAssertNotNil(lanes[0].clip)
    }

    /// Footage must never be dropped, even if its author is missing from the
    /// roster the view was handed.
    func testAClipFromOutsideTheRosterStillGetsALane() {
        let lanes = StoryGridView.lanes(
            slotClips: [clip(day: 1, authorID: "ghost")],
            members: [(id: myID, name: "Me")], myID: myID)

        XCTAssertEqual(lanes.map(\.authorID), ["ghost"])
        XCTAssertNotNil(lanes.first?.clip)
    }

    func testASoloStoryIsOneLane() {
        let lanes = StoryGridView.lanes(
            slotClips: [clip(day: 1, authorID: "local")], members: [], myID: "local")
        XCTAssertEqual(lanes.count, 1)
        XCTAssertTrue(lanes[0].isMine)
        XCTAssertNotNil(lanes[0].clip)
    }

    func testRowsSplitOnTheColumnCount() {
        let lanes = StoryGridView.lanes(
            slotClips: [
                clip(day: 1, authorID: friendID),
                clip(day: 1, authorID: myID),
                clip(day: 1, authorID: "zoe"),
            ],
            members: roster,
            myID: myID)
        XCTAssertEqual(StoryGridView.rows(of: lanes, columns: 1).count, 3)
        XCTAssertEqual(StoryGridView.rows(of: lanes, columns: 2).map(\.count), [2, 1])
    }

}
