import XCTest
@testable import AISetlog

/// Who a shared room says is in it. The old answer was a card under every
/// moment reading "waiting for Leo", which meant the rule lived in a view and
/// the only way to check it was to look at a simulator in two languages.
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

    // MARK: - Who's here

    /// Me first, then by name — the roster reads as "you and these people".
    func testTheRosterPutsMeFirstThenSortsByName() {
        let room = cast([("leo", "Leo"), ("ana", "Ana"), (myID, "Cassie")])
        XCTAssertEqual(room.rosterNames, ["Cassie", "Ana", "Leo"])
        XCTAssertEqual(room.me?.id, myID)
        XCTAssertEqual(room.others.map(\.name), ["Ana", "Leo"])
    }

    /// A room the invite never reached has nobody to name, and every line
    /// about who filmed would be a line about me.
    func testARoomOfOneHasNoCompany() {
        let room = cast([(myID, "Cassie")], clips: [clip(day: 1, authorID: myID)])
        XCTAssertFalse(room.hasCompany)
        XCTAssertNil(room.filmedNote)
        XCTAssertNil(room.waitingNote)
    }

    /// The store can list the same person twice while a room is syncing — the
    /// owner keyed by name and again by author id. Two of one face in a row of
    /// four is a room that looks bigger than it is.
    func testDuplicateMemberIDsCollapse() {
        let room = cast([("ana", "Ana"), ("ana", "Ana"), (myID, "Cassie")])
        XCTAssertEqual(room.members.count, 2)
    }

    /// The store only lists me once I'm signed in. Without me the roster
    /// reported a room of two as a room of one, hollowed out my friend, and
    /// left the person reading it off their own screen.
    func testIAmInTheRosterEvenWhenTheStoreHasntListedMe() {
        let room = cast([("ana", "Ana")], clips: [clip(day: 1, authorID: "ana")])
        XCTAssertEqual(room.rosterNames, ["Cassie", "Ana"])
        XCTAssertEqual(room.me?.id, myID)
        XCTAssertTrue(room.hasCompany)
    }

    /// With no account there is no name for me either, so the roster falls back
    /// to the word a room uses for whoever is holding the phone.
    func testASignedOutMeStillGetsAFace() {
        setLanguage(.english)
        let room = cast([("ana", "Ana")], myName: nil)
        XCTAssertEqual(room.rosterNames, ["You", "Ana"])
    }

    /// Membership syncs separately from footage, so an uploaded clip can land
    /// before its author does. A face on a thumbnail that the roster can't
    /// account for is worse than no badge at all.
    func testAnAuthorWithFootageJoinsTheRosterWithoutMembership() {
        let room = cast([(myID, "Cassie")], clips: [clip(day: 1, authorID: "zoe")])
        XCTAssertEqual(room.rosterNames, ["Cassie", "zoe"])
        XCTAssertEqual(room.othersWhoFilmed.map(\.name), ["zoe"])
    }

    /// "local" is me, not a fourth person standing next to me — a clip filed
    /// before the story was shared must not put a second face in the row.
    func testALocalClipDoesNotBecomeASecondMe() {
        let room = cast(
            [(myID, "Cassie"), ("ana", "Ana")],
            clips: [clip(day: 1, authorID: RoomProgress.soloAuthorID)])
        XCTAssertEqual(room.rosterNames, ["Cassie", "Ana"])
        XCTAssertTrue(room.iFilmed)
    }

    // MARK: - Who filmed

    func testAMemberWithAClipHasFilmed() {
        let room = cast(threePeople, clips: [clip(day: 2, authorID: "ana")])
        XCTAssertEqual(room.othersWhoFilmed.map(\.name), ["Ana"])
        XCTAssertEqual(room.othersYetToFilm.map(\.name), ["Leo"])
        XCTAssertFalse(room.iFilmed)
    }

    /// Clips filed before the story was shared are authored "local". Reading
    /// them as somebody else's would tell me I hadn't filmed my own takes.
    func testASoloClipStillCountsAsMine() {
        let room = cast(
            threePeople,
            clips: [clip(day: 1, authorID: RoomProgress.soloAuthorID)])
        XCTAssertTrue(room.iFilmed)
        XCTAssertTrue(room.namesYetToFilm.contains("Ana"))
        XCTAssertFalse(room.namesYetToFilm.contains("Cassie"))
    }

    /// The same rule `RoomProgress` counts by: a clip on a day the story
    /// doesn't have can't report somebody as having turned up.
    func testAClipOutsideTheStoryIsNotFilming() {
        let room = cast(threePeople, clips: [clip(day: 9, authorID: "ana")])
        XCTAssertTrue(room.othersWhoFilmed.isEmpty)
        XCTAssertEqual(room.namesYetToFilm, ["Cassie", "Ana", "Leo"])
    }

    /// Several takes from one person is one person, not three.
    func testSeveralClipsFromOnePersonIsOnePerson() {
        let room = cast(
            threePeople,
            clips: (1...3).map { clip(day: $0, authorID: "ana") })
        XCTAssertEqual(room.othersWhoFilmed.map(\.name), ["Ana"])
    }

    // MARK: - The lines

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

    /// The point of the line: being the only one who showed up has to be
    /// sayable, or a room reads the same whether anybody joined you or not.
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

    /// Nobody left to wait for is no line at all, not an empty one.
    func testNoWaitingLineOnceEverybodyHasFilmed() {
        let room = cast(threePeople, clips: [
            clip(day: 1, authorID: "ana"),
            clip(day: 2, authorID: "leo"),
        ])
        XCTAssertNil(room.waitingNote)
    }

    /// I am never somebody the room is waiting on — the card above is already
    /// asking me, and "waiting on Cassie" reads as a stranger's name.
    func testIAmNeverWhoTheRoomIsWaitingOn() {
        let room = cast(threePeople, clips: [
            clip(day: 1, authorID: "ana"),
            clip(day: 2, authorID: "leo"),
        ])
        XCTAssertFalse(room.iFilmed)
        XCTAssertNil(room.waitingNote)
    }

    /// A long room turns the tail of the list into a count so the line can't
    /// outgrow the screen. Faces still cover everyone — `AvatarStack` caps
    /// those itself, with its own "+N".
    func testALongListNamesTwoPeopleAndCountsTheRest() {
        let members = [(myID, "Cassie"), ("ana", "Ana"), ("bo", "Bo"), ("cy", "Cy"), ("di", "Di")]
        let room = cast(members)
        setLanguage(.chinese)
        XCTAssertEqual(room.waitingNote?.text, "在等 Ana、Bo和另外 2 人")
        setLanguage(.english)
        XCTAssertEqual(room.waitingNote?.text, "Waiting on Ana, Bo and 2 others")
        XCTAssertEqual(room.waitingNote?.names, ["Ana", "Bo", "Cy", "Di"])
    }

    /// Three people means one unnamed person, and "1 others" is the sort of
    /// thing that makes a room look machine-generated.
    func testOneUnnamedPersonReadsAsOneOther() {
        let members = [(myID, "Cassie"), ("ana", "Ana"), ("bo", "Bo"), ("cy", "Cy")]
        setLanguage(.english)
        XCTAssertEqual(cast(members).waitingNote?.text, "Waiting on Ana, Bo and 1 other")
    }

    // MARK: - The roster caption

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
