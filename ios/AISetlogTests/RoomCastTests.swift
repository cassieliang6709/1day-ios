import XCTest
@testable import AISetlog

final class RoomCastTests: XCTestCase {
    private let myID = "me"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    private func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
    }

    private func clip(day: Int, authorID: String) -> DayClip {
        DayClip(day: day, url: URL(fileURLWithPath: "/tmp/\(authorID)-\(day).mov"),
                authorName: authorID, authorID: authorID)
    }

    private func cast(
        _ members: [(id: String, name: String)],
        clips: [DayClip] = [],
        moments: Int = 5,
        myName: String? = "Cassie"
    ) -> RoomCast {
        RoomCast(
            members: members, clips: clips, momentCount: moments,
            myID: myID, myName: myName)
    }

    private var threePeople: [(id: String, name: String)] {
        [(myID, "Cassie"), ("ana", "Ana"), ("leo", "Leo")]
    }


    func testTheRosterPutsMeFirstThenSortsByName() {
        let room = cast([("leo", "Leo"), ("ana", "Ana"), (myID, "Cassie")])
        XCTAssertEqual(room.rosterNames, ["Cassie", "Ana", "Leo"])
        XCTAssertEqual(room.me?.id, myID)
        XCTAssertEqual(room.others.map(\.name), ["Ana", "Leo"])
    }

    func testARoomOfOneHasNoCompany() {
        let room = cast([(myID, "Cassie")], clips: [clip(day: 1, authorID: myID)])
        XCTAssertFalse(room.hasCompany)
        XCTAssertNil(room.filmedNote)
        XCTAssertNil(room.waitingNote)
    }

    func testDuplicateMemberIDsCollapse() {
        let room = cast([("ana", "Ana"), ("ana", "Ana"), (myID, "Cassie")])
        XCTAssertEqual(room.members.count, 2)
    }

    func testIAmInTheRosterEvenWhenTheStoreHasntListedMe() {
        let room = cast([("ana", "Ana")], clips: [clip(day: 1, authorID: "ana")])
        XCTAssertEqual(room.rosterNames, ["Cassie", "Ana"])
        XCTAssertEqual(room.me?.id, myID)
        XCTAssertTrue(room.hasCompany)
    }

    func testASignedOutMeStillGetsAFace() {
        setLanguage(.english)
        let room = cast([("ana", "Ana")], myName: nil)
        XCTAssertEqual(room.rosterNames, ["You", "Ana"])
    }

    func testAnAuthorWithFootageJoinsTheRosterWithoutMembership() {
        let room = cast([(myID, "Cassie")], clips: [clip(day: 1, authorID: "zoe")])
        XCTAssertEqual(room.rosterNames, ["Cassie", "zoe"])
        XCTAssertEqual(room.othersWhoFilmed.map(\.name), ["zoe"])
    }

    func testALocalClipDoesNotBecomeASecondMe() {
        let room = cast(
            [(myID, "Cassie"), ("ana", "Ana")],
            clips: [clip(day: 1, authorID: RoomProgress.soloAuthorID)])
        XCTAssertEqual(room.rosterNames, ["Cassie", "Ana"])
        XCTAssertTrue(room.iFilmed)
    }


    func testAMemberWithAClipHasFilmed() {
        let room = cast(threePeople, clips: [clip(day: 2, authorID: "ana")])
        XCTAssertEqual(room.othersWhoFilmed.map(\.name), ["Ana"])
        XCTAssertEqual(room.othersYetToFilm.map(\.name), ["Leo"])
        XCTAssertFalse(room.iFilmed)
    }

    func testASoloClipStillCountsAsMine() {
        let room = cast(
            threePeople,
            clips: [clip(day: 1, authorID: RoomProgress.soloAuthorID)])
        XCTAssertTrue(room.iFilmed)
        XCTAssertTrue(room.namesYetToFilm.contains("Ana"))
        XCTAssertFalse(room.namesYetToFilm.contains("Cassie"))
    }

    func testAClipOutsideTheStoryIsNotFilming() {
        let room = cast(threePeople, clips: [clip(day: 9, authorID: "ana")])
        XCTAssertTrue(room.othersWhoFilmed.isEmpty)
        XCTAssertEqual(room.namesYetToFilm, ["Cassie", "Ana", "Leo"])
    }

    func testSeveralClipsFromOnePersonIsOnePerson() {
        let room = cast(
            threePeople,
            clips: (1...3).map { clip(day: $0, authorID: "ana") })
        XCTAssertEqual(room.othersWhoFilmed.map(\.name), ["Ana"])
    }


    func testTheRoomSaysWhoFilmedInBothLanguages() {
        let room = cast(threePeople, clips: [
            clip(day: 1, authorID: "ana"),
            clip(day: 2, authorID: "leo"),
        ])
        setLanguage(.chinese)
        XCTAssertEqual(room.filmedNote?.text, "Ana和Leo拍了，就差你")
        setLanguage(.english)
        XCTAssertEqual(room.filmedNote?.text, "Ana and Leo filmed — just you left")
    }

    func testARoomWhereOnlyIFilmedSaysSo() {
        let room = cast(threePeople, clips: [clip(day: 1, authorID: myID)])
        setLanguage(.chinese)
        XCTAssertEqual(room.filmedNote?.text, "只有你拍了")
        setLanguage(.english)
        XCTAssertEqual(room.filmedNote?.text, "You're the only one so far")
    }

    func testAnUntouchedRoomSaysNobodyHasFilmed() {
        let room = cast(threePeople)
        setLanguage(.chinese)
        XCTAssertEqual(room.filmedNote?.text, "还没有人拍")
        setLanguage(.english)
        XCTAssertEqual(room.filmedNote?.text, "Nobody has filmed yet")
        XCTAssertEqual(room.filmedNote?.names, [])
    }

    func testMyOwnTakeIsCountedAlongsideTheirs() {
        let room = cast(threePeople, clips: [
            clip(day: 1, authorID: myID),
            clip(day: 2, authorID: "ana"),
        ])
        setLanguage(.chinese)
        XCTAssertEqual(room.filmedNote?.text, "你和Ana拍了")
        setLanguage(.english)
        XCTAssertEqual(room.filmedNote?.text, "You and Ana have filmed")
    }

    func testTheRoomSaysWhoItIsWaitingOn() {
        let room = cast(threePeople, clips: [clip(day: 1, authorID: "ana")])
        setLanguage(.chinese)
        XCTAssertEqual(room.waitingNote?.text, "在等 Leo")
        setLanguage(.english)
        XCTAssertEqual(room.waitingNote?.text, "Waiting on Leo")
        XCTAssertEqual(room.waitingNote?.names, ["Leo"])
    }

    func testNoWaitingLineOnceEverybodyHasFilmed() {
        let room = cast(threePeople, clips: [
            clip(day: 1, authorID: "ana"),
            clip(day: 2, authorID: "leo"),
        ])
        XCTAssertNil(room.waitingNote)
    }

    func testIAmNeverWhoTheRoomIsWaitingOn() {
        let room = cast(threePeople, clips: [
            clip(day: 1, authorID: "ana"),
            clip(day: 2, authorID: "leo"),
        ])
        XCTAssertFalse(room.iFilmed)
        XCTAssertNil(room.waitingNote)
    }

    func testALongListNamesTwoPeopleAndCountsTheRest() {
        let members = [(myID, "Cassie"), ("ana", "Ana"), ("bo", "Bo"), ("cy", "Cy"), ("di", "Di")]
        let room = cast(members)
        setLanguage(.chinese)
        XCTAssertEqual(room.waitingNote?.text, "在等 Ana、Bo和另外 2 人")
        setLanguage(.english)
        XCTAssertEqual(room.waitingNote?.text, "Waiting on Ana, Bo and 2 others")
        XCTAssertEqual(room.waitingNote?.names, ["Ana", "Bo", "Cy", "Di"])
    }

    func testOneUnnamedPersonReadsAsOneOther() {
        let members = [(myID, "Cassie"), ("ana", "Ana"), ("bo", "Bo"), ("cy", "Cy")]
        setLanguage(.english)
        XCTAssertEqual(cast(members).waitingNote?.text, "Waiting on Ana, Bo and 1 other")
    }


    func testTheRosterCaptionCountsEveryone() {
        setLanguage(.chinese)
        XCTAssertEqual(cast(threePeople).rosterLine, "3 人在这个房间")
        setLanguage(.english)
        XCTAssertEqual(cast(threePeople).rosterLine, "3 people in this room")
    }

    func testTheRosterCaptionSaysWhenNobodyElseCame() {
        setLanguage(.chinese)
        XCTAssertEqual(cast([(myID, "Cassie")]).rosterLine, "只有你在这个房间")
        setLanguage(.english)
        XCTAssertEqual(cast([(myID, "Cassie")]).rosterLine, "Just you in this room")
    }
}
