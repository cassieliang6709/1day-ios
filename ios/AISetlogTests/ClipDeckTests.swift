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


    func testMomentsComeInOrderWhateverOrderTheyArriveIn() {
        let d = deck([
            clip(day: 4, author: me),
            clip(day: 1, author: me),
            clip(day: 3, author: me),
        ])
        XCTAssertEqual(d.clips.map(\.day), [1, 3, 4])
    }

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


    func testAStoryThatWasNeverSharedIsAllMine() {
        let d = deck([clip(day: 1, author: RoomProgress.soloAuthorID)])
        XCTAssertTrue(d.isMine(at: 0))
    }

    func testAClipWithNoAuthorAtAllIsMine() {
        let d = deck([clip(day: 1, author: nil)])
        XCTAssertTrue(d.isMine(at: 0))
    }

    func testAFriendsClipIsNotMine() {
        let d = deck([clip(day: 1, author: "friend", name: "Ann")])
        XCTAssertFalse(d.isMine(at: 0))
    }


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
