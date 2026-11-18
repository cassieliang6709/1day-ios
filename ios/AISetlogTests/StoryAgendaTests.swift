import XCTest
@testable import AISetlog

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


    func testAnUntouchedStoryOffersEveryMoment() {
        let a = agenda([])
        XCTAssertEqual(a.openToMe, [1, 2, 3, 4, 5])
        XCTAssertEqual(a.filmed, [])
        XCTAssertEqual(a.filmedCount, 0)
        XCTAssertEqual(a.suggested, 1)
    }

    func testFilmingTheLastMomentFirstLeavesTheRestOpen() {
        let a = agenda([clip(day: 5, authorID: myID)])
        XCTAssertEqual(a.filmed, [5])
        XCTAssertEqual(a.openToMe, [1, 2, 3, 4])
        XCTAssertFalse(a.isComplete)
    }

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

    func testNoOpenMomentIsEverWithheld() {
        let a = agenda([clip(day: 2, authorID: myID)])
        for slot in [1, 3, 4, 5] {
            XCTAssertTrue(a.openToMe.contains(slot), "moment \(slot) fell out of the list")
        }
        XCTAssertEqual(a.openToMe.count, 4)
    }


    func testTheSuggestionIsTheEarliestMomentNobodyHasFilmed() {
        let a = agenda([clip(day: 1, authorID: myID), clip(day: 2, authorID: friendID)])
        XCTAssertEqual(a.suggested, 3)
        XCTAssertTrue(a.isSuggested(slot: 3))
        XCTAssertFalse(a.isSuggested(slot: 4))
    }

    func testTheSuggestionPointsAtAGapRatherThanTheNextSlotAlong() {
        let a = agenda([clip(day: 1, authorID: myID), clip(day: 3, authorID: myID)])
        XCTAssertEqual(a.suggested, 2)
        XCTAssertEqual(a.openToMe, [2, 4, 5])
    }

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

    func testAFullDayHasNothingLeftToSuggest() {
        let a = agenda((1...5).map { clip(day: $0, authorID: myID) })
        XCTAssertNil(a.suggested)
        XCTAssertTrue(a.isComplete)
        XCTAssertTrue(a.openToMe.isEmpty)
    }

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


    func testARoomFilledByFriendsIsCompleteAndStillOpenToMe() {
        let a = agenda((1...5).map { clip(day: $0, authorID: friendID) })
        XCTAssertTrue(a.isComplete)
        XCTAssertNil(a.suggested)
        XCTAssertEqual(a.openToMe, [1, 2, 3, 4, 5])
    }

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

    func testTwoPeopleFilmingDifferentMomentsBothLand() {
        let a = agenda([clip(day: 4, authorID: myID), clip(day: 2, authorID: friendID)])
        XCTAssertEqual(a.filmed, [2, 4])
        XCTAssertEqual(a.filmedCount, 2)
        XCTAssertEqual(a.openToMe, [1, 2, 3, 5])
        XCTAssertEqual(a.suggested, 1)
    }

    func testASoloClipCountsAsMine() {
        let a = StoryAgenda(
            momentCount: 3,
            clips: [clip(day: 1, authorID: RoomProgress.soloAuthorID)],
            myID: myID)
        XCTAssertEqual(a.filmed, [1])
        XCTAssertEqual(a.openToMe, [2, 3])
        XCTAssertFalse(a.isAwaitingMine(slot: 1))
    }


    func testClipsOutsideTheStoryAreIgnored() {
        let a = agenda([clip(day: 9, authorID: myID), clip(day: 0, authorID: myID)])
        XCTAssertEqual(a.filmed, [])
        XCTAssertEqual(a.filmedCount, 0)
        XCTAssertEqual(a.openToMe, [1, 2, 3, 4, 5])
        XCTAssertEqual(a.suggested, 1)
    }

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
