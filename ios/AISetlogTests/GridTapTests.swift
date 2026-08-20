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
}
