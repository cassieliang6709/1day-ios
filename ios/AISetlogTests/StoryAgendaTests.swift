import XCTest
@testable import AISetlog

/// The story page shows exactly one next thing, so which moment that is has to
/// be decided somewhere testable rather than inferred from tile tints.
final class StoryAgendaTests: XCTestCase {
    private let myID = "me"
    private let friendID = "friend"

    private func clip(day: Int, authorID: String) -> DayClip {
        DayClip(day: day, url: URL(fileURLWithPath: "/tmp/\(authorID)-\(day).mov"),
                authorName: authorID, authorID: authorID)
    }

    private func agenda(_ clips: [DayClip], moments: Int = 5) -> StoryAgenda {
        StoryAgenda(momentCount: moments, clips: clips, myID: myID)
    }

    // MARK: - What's next

    func testAnUntouchedStoryOffersItsFirstMoment() {
        XCTAssertEqual(agenda([]).next, .film(slot: 1))
        XCTAssertEqual(agenda([]).filmed, [])
        XCTAssertEqual(agenda([]).filmedCount, 0)
    }

    func testTheNextMomentIsTheFirstOneNobodyHasFilmed() {
        let a = agenda([clip(day: 1, authorID: myID), clip(day: 2, authorID: friendID)])
        XCTAssertEqual(a.next, .film(slot: 3))
    }

    /// Gaps are filled before the day moves on: filming out of order shouldn't
    /// make the page skip the hole it left behind.
    func testAGapIsOfferedBeforeLaterEmptySlots() {
        let a = agenda([clip(day: 1, authorID: myID), clip(day: 3, authorID: myID)])
        XCTAssertEqual(a.next, .film(slot: 2))
    }

    func testAFullDayOffersTheFilmInstead() {
        let clips = (1...5).map { clip(day: $0, authorID: myID) }
        let a = agenda(clips)
        XCTAssertEqual(a.next, .watchTheFilm)
        XCTAssertTrue(a.isComplete)
        XCTAssertTrue(a.later.isEmpty)
    }

    /// A room finishes when the room finishes. Two friends filming the whole
    /// day between them is a complete story even though I filmed none of it.
    func testARoomFilledByFriendsIsCompleteAndStillOpenToMe() {
        let clips = (1...5).map { clip(day: $0, authorID: friendID) }
        let a = agenda(clips)
        XCTAssertEqual(a.next, .watchTheFilm)
        XCTAssertTrue(a.isComplete)
        XCTAssertEqual(a.openToMe, [1, 2, 3, 4, 5])
        XCTAssertEqual(a.later, [1, 2, 3, 4, 5])
    }

    func testAStoryWithNoMomentsStillPointsSomewhere() {
        XCTAssertEqual(
            StoryAgenda(momentCount: 0, clips: [], myID: myID).next, .film(slot: 1))
        XCTAssertFalse(StoryAgenda(momentCount: 0, clips: [], myID: myID).isComplete)
    }

    // MARK: - Reachability

    /// A moment a friend filmed first has to stay reachable. The grid used to
    /// turn that tile into their take and offer no way to add mine, so the
    /// slot stays in `openToMe` and keeps its row in the quiet list.
    func testAMomentOnlyAFriendFilmedStaysOpenToMe() {
        let a = agenda([clip(day: 2, authorID: friendID)])
        XCTAssertEqual(a.filmed, [2])
        XCTAssertTrue(a.openToMe.contains(2))
        XCTAssertTrue(a.isAwaitingMine(slot: 2))
    }

    func testAMomentIFilmedIsNotAwaitingMine() {
        let a = agenda([clip(day: 2, authorID: myID)])
        XCTAssertFalse(a.isAwaitingMine(slot: 2))
        XCTAssertFalse(a.openToMe.contains(2))
    }

    /// Solo stories attribute clips to "local" rather than an account id.
    func testASoloClipCountsAsMine() {
        let a = StoryAgenda(
            momentCount: 3,
            clips: [clip(day: 1, authorID: RoomProgress.soloAuthorID)],
            myID: myID)
        XCTAssertEqual(a.filmed, [1])
        XCTAssertEqual(a.openToMe, [2, 3])
        XCTAssertFalse(a.isAwaitingMine(slot: 1))
    }

    // MARK: - The quiet list

    /// The list under the card never repeats the card.
    func testTheQuietListLeavesOutTheMomentOnTheCard() {
        let a = agenda([clip(day: 1, authorID: myID)])
        XCTAssertEqual(a.next, .film(slot: 2))
        XCTAssertEqual(a.later, [3, 4, 5])
    }

    // MARK: - Stray clips

    /// A clip whose day is outside the story can't report a moment the story
    /// doesn't have — the same rule `RoomProgress` counts by.
    func testClipsOutsideTheStoryAreIgnored() {
        let a = agenda([clip(day: 9, authorID: myID), clip(day: 0, authorID: myID)])
        XCTAssertEqual(a.filmed, [])
        XCTAssertEqual(a.filmedCount, 0)
        XCTAssertEqual(a.next, .film(slot: 1))
    }

    /// Several people on one moment is one filmed moment, not three.
    func testSeveralTakesOfOneMomentCountOnce() {
        let a = agenda([
            clip(day: 1, authorID: myID),
            clip(day: 1, authorID: friendID),
            clip(day: 1, authorID: "zoe"),
        ])
        XCTAssertEqual(a.filmed, [1])
        XCTAssertEqual(a.filmedCount, 1)
    }
}
