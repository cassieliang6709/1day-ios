import XCTest
@testable import AISetlog

/// A story is filmed in whatever order the day happens in, so the thing that
/// has to hold under test is that nothing narrows: every moment I haven't
/// filmed stays in `openToMe` however the clips arrive, and the one suggestion
/// on top of that never removes anything from the list.
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

    // MARK: - Any order

    /// The list is the offer. Nothing is held back for a card above it, so an
    /// untouched story shows all five moments and none of them is special
    /// apart from the wording on one row.
    func testAnUntouchedStoryOffersEveryMoment() {
        let a = agenda([])
        XCTAssertEqual(a.openToMe, [1, 2, 3, 4, 5])
        XCTAssertEqual(a.filmed, [])
        XCTAssertEqual(a.filmedCount, 0)
        XCTAssertEqual(a.suggested, 1)
    }

    /// Filming the last moment first is a normal way to use this app, not a
    /// state to recover from: the other four stay open, in day order.
    func testFilmingTheLastMomentFirstLeavesTheRestOpen() {
        let a = agenda([clip(day: 5, authorID: myID)])
        XCTAssertEqual(a.filmed, [5])
        XCTAssertEqual(a.openToMe, [1, 2, 3, 4])
        XCTAssertFalse(a.isComplete)
    }

    /// Jumping around fills the story exactly the same way filming in order
    /// would. The counts follow the clips, not the sequence they arrived in.
    func testFilmingOutOfOrderCountsTheSameAsInOrder() {
        let jumped = agenda([
            clip(day: 4, authorID: myID),
            clip(day: 1, authorID: myID),
            clip(day: 3, authorID: myID),
        ])
        let ordered = agenda((1...3).map { clip(day: $0, authorID: myID) })

        XCTAssertEqual(jumped.filmedCount, ordered.filmedCount)
        XCTAssertEqual(jumped.filmed, [1, 3, 4])
        XCTAssertEqual(jumped.openToMe, [2, 5])
        XCTAssertEqual(jumped.openToMe.count, ordered.openToMe.count)
    }

    /// Every open moment is reachable at once — that is the whole point, and
    /// it's the one thing an "open list minus the featured one" could break.
    func testNoOpenMomentIsEverWithheld() {
        let a = agenda([clip(day: 2, authorID: myID)])
        for slot in [1, 3, 4, 5] {
            XCTAssertTrue(a.openToMe.contains(slot), "moment \(slot) fell out of the list")
        }
        XCTAssertEqual(a.openToMe.count, 4)
    }

    // MARK: - The suggestion

    /// A hint, and only ever one row's worth of difference.
    func testTheSuggestionIsTheEarliestMomentNobodyHasFilmed() {
        let a = agenda([clip(day: 1, authorID: myID), clip(day: 2, authorID: friendID)])
        XCTAssertEqual(a.suggested, 3)
        XCTAssertTrue(a.isSuggested(slot: 3))
        XCTAssertFalse(a.isSuggested(slot: 4))
    }

    /// Filming out of order leaves a hole, and the hint points at the hole
    /// rather than at the end of the day — a room gets more from an untouched
    /// moment than from a fourth take of breakfast. It's still only a hint:
    /// moments 4 and 5 are in the list beside it.
    func testTheSuggestionPointsAtAGapRatherThanTheNextSlotAlong() {
        let a = agenda([clip(day: 1, authorID: myID), clip(day: 3, authorID: myID)])
        XCTAssertEqual(a.suggested, 2)
        XCTAssertEqual(a.openToMe, [2, 4, 5])
    }

    /// The suggested row is always one of the rows on screen, so the tint can
    /// never land on a moment the list isn't showing.
    func testTheSuggestionIsAlwaysOneOfTheOpenMoments() {
        let cases: [[DayClip]] = [
            [],
            [clip(day: 3, authorID: myID)],
            [clip(day: 1, authorID: friendID), clip(day: 2, authorID: friendID)],
            [clip(day: 5, authorID: myID), clip(day: 4, authorID: friendID)],
        ]
        for clips in cases {
            let a = agenda(clips)
            guard let suggested = a.suggested else { continue }
            XCTAssertTrue(a.openToMe.contains(suggested), "suggested \(suggested) isn't listed")
        }
    }

    /// Nothing left to suggest once every moment holds footage — the page has
    /// a film to offer instead.
    func testAFullDayHasNothingLeftToSuggest() {
        let a = agenda((1...5).map { clip(day: $0, authorID: myID) })
        XCTAssertNil(a.suggested)
        XCTAssertTrue(a.isComplete)
        XCTAssertTrue(a.openToMe.isEmpty)
    }

    /// A moment somebody filmed is never the suggested one, so no row can be
    /// asked to say "start here?" and "add yours" at the same time.
    func testASuggestedMomentIsNeverOneAwaitingMine() {
        let a = agenda([clip(day: 1, authorID: friendID), clip(day: 2, authorID: friendID)])
        XCTAssertEqual(a.suggested, 3)
        XCTAssertTrue(a.isAwaitingMine(slot: 1))
        XCTAssertFalse(a.isSuggested(slot: 1))
        XCTAssertFalse(a.isAwaitingMine(slot: 3))
    }

    func testAStoryWithNoMomentsSuggestsNothing() {
        let a = StoryAgenda(momentCount: 0, clips: [], myID: myID)
        XCTAssertNil(a.suggested)
        XCTAssertTrue(a.openToMe.isEmpty)
        XCTAssertFalse(a.isComplete)
    }

    // MARK: - Rooms

    /// A room finishes when the room finishes. Two friends filming the whole
    /// day between them is a complete story even though I filmed none of it —
    /// and every one of those moments is still open for my take.
    func testARoomFilledByFriendsIsCompleteAndStillOpenToMe() {
        let a = agenda((1...5).map { clip(day: $0, authorID: friendID) })
        XCTAssertTrue(a.isComplete)
        XCTAssertNil(a.suggested)
        XCTAssertEqual(a.openToMe, [1, 2, 3, 4, 5])
    }

    /// A moment a friend filmed first has to stay reachable. The grid used to
    /// turn that tile into their take and offer no way to add mine, so the
    /// slot stays in `openToMe` and keeps its row in the list.
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

    /// Two people picking different moments at the same time is the room
    /// working as intended, not a conflict to resolve.
    func testTwoPeopleFilmingDifferentMomentsBothLand() {
        let a = agenda([clip(day: 4, authorID: myID), clip(day: 2, authorID: friendID)])
        XCTAssertEqual(a.filmed, [2, 4])
        XCTAssertEqual(a.filmedCount, 2)
        XCTAssertEqual(a.openToMe, [1, 2, 3, 5])
        XCTAssertEqual(a.suggested, 1)
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

    // MARK: - Stray clips

    /// A clip whose day is outside the story can't report a moment the story
    /// doesn't have — the same rule `RoomProgress` counts by.
    func testClipsOutsideTheStoryAreIgnored() {
        let a = agenda([clip(day: 9, authorID: myID), clip(day: 0, authorID: myID)])
        XCTAssertEqual(a.filmed, [])
        XCTAssertEqual(a.filmedCount, 0)
        XCTAssertEqual(a.openToMe, [1, 2, 3, 4, 5])
        XCTAssertEqual(a.suggested, 1)
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
