import XCTest
@testable import AISetlog

/// A moment a friend filmed first has to stay reachable: the tile shows their
/// take, but tapping it is still how I film mine. The grid used to open the
/// viewer whenever anyone had filmed the slot, which made those moments
/// impossible to fill from this view — the timeline had a slot for me, the
/// grid didn't.
final class GridTapTests: XCTestCase {
    private let myID = "me"
    private let friendID = "friend"

    private func clip(day: Int, authorID: String) -> DayClip {
        DayClip(day: day, url: URL(fileURLWithPath: "/tmp/\(authorID)-\(day).mov"),
                authorName: authorID, authorID: authorID)
    }

    func testAnEmptyMomentRecords() {
        XCTAssertEqual(StoryGridView.tap(slotClips: [], myID: myID), .record)
    }

    func testAMomentOnlyAFriendFilmedStillRecords() {
        let slot = [clip(day: 1, authorID: friendID)]
        XCTAssertEqual(StoryGridView.tap(slotClips: slot, myID: myID), .record)
    }

    func testAMomentIFilmedPreviews() {
        let slot = [clip(day: 1, authorID: friendID), clip(day: 1, authorID: myID)]
        XCTAssertEqual(StoryGridView.tap(slotClips: slot, myID: myID), .preview(authorID: myID))
    }

    /// Solo stories attribute clips to "local" rather than an account id.
    func testASoloClipCountsAsMine() {
        let slot = [clip(day: 1, authorID: "local")]
        XCTAssertEqual(StoryGridView.tap(slotClips: slot, myID: myID), .preview(authorID: "local"))
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
