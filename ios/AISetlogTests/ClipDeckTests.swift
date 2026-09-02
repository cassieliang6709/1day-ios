import XCTest
@testable import AISetlog

final class ClipDeckTests: XCTestCase {
    private let me = "author-me"

    private func clip(
        day: Int, author: String?, name: String? = nil, label: String? = nil, key: String? = nil
    ) -> DayClip {
        DayClip(
            day: day,
            url: URL(fileURLWithPath: "/tmp/\(key ?? "\(day)-\(author ?? "nil")").mov"),
            authorName: name,
            authorID: author,
            label: label,
            key: key ?? "\(day)-\(author ?? "nil")")
    }

    private func deck(_ clips: [DayClip], momentCount: Int = 5) -> ClipDeck {
        ClipDeck(clips: clips, momentCount: momentCount, myID: me)
    }

    // MARK: Order

    func testMomentsComeInOrderWhateverOrderTheyArriveIn() {
        let d = deck([
            clip(day: 4, author: me),
            clip(day: 1, author: me),
            clip(day: 3, author: me),
        ])
        XCTAssertEqual(d.clips.map(\.day), [1, 3, 4])
    }

    /// The bug this whole type exists to fix. The store hands clips over sorted
    /// by `(day, authorName)`, so in a room with Ava in it my own take on a
    /// moment came second — my tile sat to the right of hers and my page opened
    /// after hers. Whose day this is shouldn't depend on the alphabet.
    func testMyTakeComesFirstEvenWhenMyNameSortsLast() {
        let d = deck([
            clip(day: 1, author: "friend-ava", name: "Ava"),
            clip(day: 1, author: me, name: "Zoe"),
            clip(day: 1, author: "friend-bo", name: "Bo"),
        ])
        XCTAssertEqual(d.clips.map(\.authorName), ["Zoe", "Ava", "Bo"])
        XCTAssertTrue(d.isMine(at: 0))
    }

    func testFriendsAreOrderedByName() {
        let d = deck([
            clip(day: 2, author: "f-c", name: "Cara"),
            clip(day: 2, author: "f-a", name: "Ann"),
            clip(day: 2, author: "f-b", name: "Bo"),
        ])
        XCTAssertEqual(d.clips.map(\.authorName), ["Ann", "Bo", "Cara"])
    }

    /// Two people can pick the same display name. Without a final tiebreak the
    /// sort is unstable, and a deck that reorders between two reads hands the
    /// pager a different page for the same tile.
    func testTwoFriendsWithOneNameStillGetAFixedOrder() {
        let first = deck([
            clip(day: 1, author: "f-2", name: "Sam", key: "k2"),
            clip(day: 1, author: "f-1", name: "Sam", key: "k1"),
        ])
        let second = deck([
            clip(day: 1, author: "f-1", name: "Sam", key: "k1"),
            clip(day: 1, author: "f-2", name: "Sam", key: "k2"),
        ])
        XCTAssertEqual(first.clips.map(\.id), ["k1", "k2"])
        XCTAssertEqual(first.clips.map(\.id), second.clips.map(\.id))
    }

    func testTheTableIsReadMomentByMomentNotPersonByPerson() {
        let d = deck([
            clip(day: 2, author: "f-a", name: "Ann", key: "a2"),
            clip(day: 1, author: "f-a", name: "Ann", key: "a1"),
            clip(day: 2, author: me, name: "Me", key: "m2"),
            clip(day: 1, author: me, name: "Me", key: "m1"),
        ])
        XCTAssertEqual(d.clips.map(\.id), ["m1", "a1", "m2", "a2"])
    }

    // MARK: Whose is it

    func testAStoryThatWasNeverSharedIsAllMine() {
        let d = deck([clip(day: 1, author: RoomProgress.soloAuthorID)])
        XCTAssertTrue(d.isMine(at: 0))
    }

    /// Clips saved before authorship existed carry no author. Reading those as
    /// somebody else's would hide the re-record button on my own clip.
    func testAClipWithNoAuthorAtAllIsMine() {
        let d = deck([clip(day: 1, author: nil)])
        XCTAssertTrue(d.isMine(at: 0))
    }

    func testAFriendsClipIsNotMine() {
        let d = deck([clip(day: 1, author: "friend", name: "Ann")])
        XCTAssertFalse(d.isMine(at: 0))
    }

    // MARK: Finding a tap

    func testTappingATileOpensThatTile() {
        let d = deck([
            clip(day: 1, author: me, name: "Me"),
            clip(day: 1, author: "f-a", name: "Ann"),
            clip(day: 3, author: "f-a", name: "Ann"),
        ])
        XCTAssertEqual(d.index(ofDay: 1, authorID: me), 0)
        XCTAssertEqual(d.index(ofDay: 1, authorID: "f-a"), 1)
        XCTAssertEqual(d.index(ofDay: 3, authorID: "f-a"), 2)
    }

    /// nil, "local" and my own id all mean the same tile.
    func testTheThreeWaysOfSayingMineAllFindMine() {
        let d = deck([
            clip(day: 1, author: "f-a", name: "Ann"),
            clip(day: 1, author: me, name: "Me"),
        ])
        XCTAssertEqual(d.index(ofDay: 1, authorID: nil), 0)
        XCTAssertEqual(d.index(ofDay: 1, authorID: me), 0)
        XCTAssertEqual(d.index(ofDay: 1, authorID: RoomProgress.soloAuthorID), 0)
    }

    func testAMomentNobodyFilmedHasNoPage() {
        let d = deck([clip(day: 1, author: me)])
        XCTAssertNil(d.index(ofDay: 2, authorID: nil))
        XCTAssertNil(d.index(ofDay: 1, authorID: "someone-who-didnt"))
    }

    // MARK: Which players stay alive

    func testOnlyThePageYoureOnAndItsNeighboursAreLive() {
        let d = deck((1...5).map { clip(day: $0, author: me) })
        XCTAssertEqual(d.liveIndices(around: 2), [1, 2, 3])
    }

    func testTheWindowClampsAtBothEnds() {
        let d = deck((1...5).map { clip(day: $0, author: me) })
        XCTAssertEqual(d.liveIndices(around: 0), [0, 1])
        XCTAssertEqual(d.liveIndices(around: 4), [3, 4])
    }

    func testNothingIsLiveOffTheEnd() {
        let d = deck([clip(day: 1, author: me)])
        XCTAssertEqual(d.liveIndices(around: 7), [])
        XCTAssertEqual(deck([]).liveIndices(around: 0), [])
    }

    // MARK: The chip over the video

    func testTheChipNamesTheMomentAndDoesNotNameMe() {
        let d = deck([clip(day: 2, author: me, name: "Me", label: "Golden hour")])
        XCTAssertEqual(
            d.position(at: 0),
            ClipDeck.Position(day: 2, momentCount: 5, label: "Golden hour", authorName: nil))
    }

    func testTheChipNamesAFriend() {
        let d = deck([clip(day: 2, author: "f-a", name: "Ann", label: "Golden hour")])
        XCTAssertEqual(d.position(at: 0)?.authorName, "Ann")
    }

    /// A clip can outlive the story it was filmed for — trimming the prompt list
    /// leaves day 6 sitting in a 5-slot story. It should still be watchable, and
    /// the chip should not read "6 / 5".
    func testAClipPastTheEndOfTheStoryStillCounts() {
        let d = deck([clip(day: 6, author: me)], momentCount: 5)
        XCTAssertEqual(d.position(at: 0)?.momentCount, 6)
    }

    func testAnEmptyDeckHasNoPositionAndNoClip() {
        let d = deck([])
        XCTAssertTrue(d.isEmpty)
        XCTAssertEqual(d.count, 0)
        XCTAssertNil(d.position(at: 0))
        XCTAssertNil(d.clip(at: 0))
        XCTAssertFalse(d.isMine(at: 0))
    }
}
