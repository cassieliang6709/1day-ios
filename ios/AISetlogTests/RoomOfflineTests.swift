import XCTest
@testable import AISetlog

/// The parts of a shared room that don't need CloudKit on the line.
///
/// Everything the four `CloudKit*`/`RoomSync*`/`JoinedRoom*` suites check needs
/// a simulator signed into iCloud, which CI hasn't got — so the room has spent
/// its life verified by hand or not at all. These are the rules that survive
/// unplugging the network: which code opens which room, whose clip is whose
/// once the room's copies and this phone's copies meet, and what signing out
/// is supposed to take with it.
@MainActor
final class RoomOfflineTests: XCTestCase {
    private var files: RecordingClipFileStore!
    private var sync: RoomSyncService!
    private var store: ChallengeStore!
    private var me: AccountStore.Account!

    override func setUp() {
        super.setUp()
        files = RecordingClipFileStore()
        sync = RoomSyncService(fileStore: files)
        store = ChallengeStore(
            repository: MemoryChallengeRepository(), fileStore: files, roomSync: sync)
        let account = AccountStore()
        account.signInAsTester(named: "Me")
        store.account = account
        me = account.account
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "account.v1")
        store = nil
        sync = nil
        files = nil
        me = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func sharedChallenge(
        code: String = "KPADC7",
        moments: Int = 3,
        ownerID: String? = "owner-1",
        ownerName: String? = "Leo",
        filmedDays: [Int] = []
    ) -> Challenge {
        Challenge(
            id: UUID(),
            title: "A perfect day",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            cards: (1...moments).map { day in
                DayCard(
                    day: day,
                    clipFileName: filmedDays.contains(day) ? "day\(day).mov" : nil,
                    recordedAt: filmedDays.contains(day)
                        ? Date(timeIntervalSince1970: 1_700_000_000) : nil)
            },
            mode: .oneDay,
            clipLength: .tiny,
            orientation: .portrait,
            momentTitles: (1...moments).map { "Moment \($0)" },
            roomCode: code,
            ownerName: ownerName,
            ownerID: ownerID)
    }

    private func remoteClip(
        code: String = "KPADC7", day: Int, authorID: String, authorName: String
    ) -> CloudKitService.RemoteClip {
        CloudKitService.RemoteClip(
            id: CloudKitService.clipRecordName(code: code, authorID: authorID, day: day),
            day: day,
            authorID: authorID,
            authorName: authorName,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_100),
            localURL: URL(fileURLWithPath: "/tmp/room/\(code)_\(authorID)_day\(day).mov"),
            overlayText: nil)
    }

    // MARK: - Getting into a room

    /// The code you already hold opens the room you already have, however it
    /// was typed — no second copy of the same story on the home screen, and no
    /// network needed to work that out.
    func testACodeIAlreadyHoldJustOpensThatRoom() async throws {
        let room = sharedChallenge(code: "KPADC7")
        store.challenges = [room]

        for typed in ["KPADC7", "kpadc7", "  kpadc7  ", "kp-adc7", "kp adc 7"] {
            let opened = try await store.joinRoom(code: typed)
            XCTAssertEqual(opened.id, room.id, "‘\(typed)’ should open the room I'm in")
        }
        XCTAssertEqual(store.challenges.count, 1, "joining again must not duplicate the room")
    }

    /// A code that can't be a code is refused here rather than at the far end
    /// of a round trip. On a machine without iCloud the round trip's first
    /// answer is "sign into iCloud", which is not what's wrong.
    func testACodeThatCannotExistIsRefusedBeforeAnyNetworkCall() async {
        for impossible in ["AB0DEF", "ABIDEF", "KPADC", "", "邀请码在这里"] {
            do {
                _ = try await store.joinRoom(code: impossible)
                XCTFail("‘\(impossible)’ is not a code and should not have joined anything")
            } catch CloudKitService.CKServiceError.roomNotFound {
                // Right answer: no such room, rather than an iCloud problem.
            } catch {
                XCTFail("‘\(impossible)’ threw the wrong thing: \(error)")
            }
        }
        XCTAssertTrue(store.challenges.isEmpty)
    }

    func testJoiningWithoutSigningInIsRefused() async {
        store.account = nil
        do {
            _ = try await store.joinRoom(code: "KPADC7")
            XCTFail("a signed-out person has no author id to join as")
        } catch ChallengeStore.RoomError.notSignedIn {
            // Right answer.
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Whose clip is whose

    /// The room's copy of my clip and this phone's copy are one clip. Listing
    /// both put me on screen twice in my own film.
    func testMyUploadedTakeIsNotAlsoListedFromThisPhone() {
        let room = sharedChallenge(filmedDays: [1])
        store.challenges = [room]
        sync.remoteClips["KPADC7"] = [
            remoteClip(day: 1, authorID: me.id, authorName: "Me"),
        ]

        let clips = store.recordedClips(for: room.id)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clips.first?.authorID, me.id)
        XCTAssertEqual(
            clips.first?.url.lastPathComponent, "KPADC7_\(me.id)_day1.mov",
            "the room's copy is the one everybody else is watching")
    }

    /// A moment I filmed but haven't uploaded is still mine and still in the
    /// day. Dropping it would make my own footage disappear the moment a
    /// friend's clip arrived.
    func testAClipStillOnThisPhoneShowsUpBesideTheRoomsCopies() {
        let room = sharedChallenge(filmedDays: [2])
        store.challenges = [room]
        sync.remoteClips["KPADC7"] = [
            remoteClip(day: 1, authorID: "owner-1", authorName: "Leo"),
        ]

        let clips = store.recordedClips(for: room.id)
        XCTAssertEqual(clips.map(\.day), [1, 2])
        XCTAssertEqual(clips.first?.authorID, "owner-1")
        XCTAssertEqual(clips.last?.authorID, me.id)
        XCTAssertEqual(clips.last?.url.lastPathComponent, "day2.mov")
    }

    /// Two people filming the same moment is the point of a room, not a
    /// collision — both takes play.
    func testTwoPeoplesTakesOfOneMomentBothSurvive() {
        let room = sharedChallenge()
        store.challenges = [room]
        sync.remoteClips["KPADC7"] = [
            remoteClip(day: 1, authorID: me.id, authorName: "Me"),
            remoteClip(day: 1, authorID: "owner-1", authorName: "Leo"),
        ]

        let clips = store.recordedClips(for: room.id)
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips.map(\.authorName), ["Leo", "Me"], "ordered by day, then by name")
        XCTAssertEqual(Set(clips.map(\.id)).count, 2, "two clips, two identities")
    }

    /// A room nobody has filmed in yet still has to show me my own cards —
    /// the empty-remote path is the one a guest sees for their first minute.
    func testARoomWithNothingInItStillShowsMyOwnCards() {
        let room = sharedChallenge(filmedDays: [1, 2])
        store.challenges = [room]
        sync.remoteClips["KPADC7"] = []

        let clips = store.recordedClips(for: room.id)
        XCTAssertEqual(clips.map(\.day), [1, 2])
        XCTAssertTrue(clips.allSatisfy { $0.authorID == self.me.id })
    }

    func testAStoryThatWasNeverSharedListsOnlyMyOwnCards() {
        var solo = sharedChallenge(filmedDays: [1])
        solo.roomCode = nil
        solo.ownerID = nil
        solo.ownerName = nil
        store.challenges = [solo]

        let clips = store.recordedClips(for: solo.id)
        XCTAssertEqual(clips.map(\.day), [1])
        XCTAssertEqual(clips.first?.authorID, me.id)
    }

    // MARK: - Who is in the room

    /// The host is in the roster before they've filmed anything, or somebody
    /// who just typed a code sees a room containing only themselves and can't
    /// tell whether it worked.
    func testTheOwnerIsInTheRosterBeforeAnybodyHasFilmed() {
        let room = sharedChallenge()
        store.challenges = [room]

        let names = store.members(for: room.id).map(\.name).sorted()
        XCTAssertEqual(names, ["Leo", "Me"])
    }

    /// Rooms saved before `ownerID` existed key the host by their name. Once
    /// the same person turns up under a real author id, the placeholder has to
    /// go — otherwise the host stands in the roster twice.
    func testAnOwnerRememberedOnlyByNameStepsAsideForTheirRealIdentity() {
        let room = sharedChallenge(ownerID: nil, ownerName: "Leo")
        store.challenges = [room]
        sync.remoteClips["KPADC7"] = [
            remoteClip(day: 1, authorID: "owner-1", authorName: "Leo"),
        ]

        let members = store.members(for: room.id)
        XCTAssertEqual(members.map(\.name).sorted(), ["Leo", "Me"])
        XCTAssertEqual(members.first { $0.name == "Leo" }?.id, "owner-1")
    }

    func testAStoryWithNoRoomHasNoRoster() {
        var solo = sharedChallenge()
        solo.roomCode = nil
        store.challenges = [solo]
        XCTAssertTrue(store.members(for: solo.id).isEmpty)
    }

    // MARK: - Signing out

    /// The cache is keyed by author id and signing out changes who I am. Left
    /// behind, my own uploads became a stranger's: the roster still listed me,
    /// every empty slot read "waiting for <my own name>", and the header
    /// credited my takes to somebody else.
    func testSigningOutForgetsWhatEveryRoomDownloaded() {
        let first = sharedChallenge(code: "KPADC7")
        let second = sharedChallenge(code: "GPP5RL")
        store.challenges = [first, second]
        for code in ["KPADC7", "GPP5RL"] {
            sync.remoteClips[code] = [
                remoteClip(code: code, day: 1, authorID: me.id, authorName: "Me"),
            ]
            sync.remoteReactions[code] = [
                CloudKitService.RemoteReaction(
                    day: 1, emoji: "🔥", authorID: "owner-1", authorName: "Leo",
                    targetAuthorID: me.id, createdAt: Date(timeIntervalSince1970: 1)),
            ]
            sync.remoteComments[code] = [
                CloudKitService.RemoteComment(
                    id: UUID().uuidString, day: 1, text: "nice",
                    authorID: "owner-1", authorName: "Leo",
                    targetAuthorID: me.id, createdAt: Date(timeIntervalSince1970: 1)),
            ]
        }

        store.signOut()

        for code in ["KPADC7", "GPP5RL"] {
            XCTAssertNil(sync.remoteClips[code], "\(code) still holds downloaded clips")
            XCTAssertNil(sync.remoteReactions[code], "\(code) still holds reactions")
            XCTAssertNil(sync.remoteComments[code], "\(code) still holds comments")
        }
        XCTAssertEqual(
            Set(files.deletedRemoteCaches), ["KPADC7", "GPP5RL"],
            "every room's downloaded files have to go, not just the first")
        XCTAssertFalse(store.account?.isSignedIn ?? true)
        XCTAssertEqual(store.challenges.count, 2, "the stories stay; only the borrowed copies go")
    }

    /// After signing out my own clips read as nobody's rather than as the next
    /// person's — the whole point of clearing the cache.
    func testAfterSigningOutTheRoomShowsNobodysFootage() {
        let room = sharedChallenge(filmedDays: [1])
        store.challenges = [room]
        sync.remoteClips["KPADC7"] = [remoteClip(day: 1, authorID: me.id, authorName: "Me")]

        store.signOut()

        let clips = store.recordedClips(for: room.id)
        XCTAssertEqual(clips.map(\.day), [1], "my own card is still on this phone")
        XCTAssertEqual(
            clips.first?.authorID, RoomProgress.soloAuthorID,
            "with nobody signed in, my clip is mine-on-this-device, not a stranger's")
    }

    // MARK: - Writing the same thing twice

    /// Every write in a room lands on a name the app derives rather than one
    /// CloudKit hands back, which is the entire reason a retry, a double tap
    /// or a second device replaying the same upload is harmless. That promise
    /// is a property of these strings, so it can be checked without a network.
    func testTheSameClipAlwaysDerivesTheSameRecordName() {
        let first = CloudKitService.clipRecordName(code: "KPADC7", authorID: "a-1", day: 3)
        let again = CloudKitService.clipRecordName(code: "KPADC7", authorID: "a-1", day: 3)
        XCTAssertEqual(first, again)
        XCTAssertEqual(first, "KPADC7_a-1_day3")
    }

    func testADifferentPersonDayOrRoomIsADifferentRecord() {
        let mine = CloudKitService.clipRecordName(code: "KPADC7", authorID: "a-1", day: 3)
        XCTAssertNotEqual(mine, CloudKitService.clipRecordName(code: "KPADC7", authorID: "a-2", day: 3))
        XCTAssertNotEqual(mine, CloudKitService.clipRecordName(code: "KPADC7", authorID: "a-1", day: 4))
        XCTAssertNotEqual(mine, CloudKitService.clipRecordName(code: "GPP5RL", authorID: "a-1", day: 3))
    }

    /// Idempotent only counts if the name is also *unambiguous*: every distinct
    /// (room, person, moment) has to land somewhere no other one does, or a
    /// harmless-looking overwrite quietly replaces somebody else's clip. Real
    /// author ids are Sign in with Apple strings and `tester-<uuid>`, so the
    /// awkward ones are covered here too — an id carrying an underscore, and
    /// one that is another id with a day glued onto it.
    func testEveryPersonAndMomentLandsOnItsOwnRecord() {
        let codes = ["KPADC7", "GPP5RL"]
        let authors = ["a", "a_day1", "a-1", "001234.abcd.5678", "tester-\(UUID().uuidString)"]
        let days = [1, 2, 11, 12]

        var names: Set<String> = []
        var expected = 0
        for code in codes {
            for author in authors {
                for day in days {
                    names.insert(CloudKitService.clipRecordName(
                        code: code, authorID: author, day: day))
                    expected += 1
                }
            }
        }
        XCTAssertEqual(
            names.count, expected,
            "two different clips derived the same record name and would overwrite each other")
    }

    func testTheSameReactionAlwaysDerivesTheSameRecordName() {
        let name = { (emoji: String) in
            CloudKitService.reactionRecordName(
                code: "KPADC7", targetAuthorID: "a-1", authorID: "a-2", day: 3, emoji: emoji)
        }
        XCTAssertEqual(name("🔥"), name("🔥"))
        XCTAssertNotEqual(name("🔥"), name("❤️"))
        XCTAssertNotEqual(
            name("🔥"),
            CloudKitService.reactionRecordName(
                code: "KPADC7", targetAuthorID: "a-2", authorID: "a-1", day: 3, emoji: "🔥"),
            "reacting to somebody is not the same as them reacting to you")
    }

    /// An emoji record name is built out of unicode scalar values on purpose:
    /// a CloudKit record name has to stay inside a plain ASCII alphabet, and a
    /// multi-scalar emoji like ❤️ would otherwise smuggle a variation selector
    /// into it.
    func testAReactionRecordNameIsSomethingCloudKitWillAccept() {
        for emoji in ["🔥", "❤️", "👍🏽", "🎉"] {
            let name = CloudKitService.reactionRecordName(
                code: "KPADC7", targetAuthorID: "a-1", authorID: "a-2", day: 3, emoji: emoji)
            XCTAssertTrue(
                name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_-.".contains($0)) },
                "\(emoji) produced a record name CloudKit would refuse: \(name)")
            XCTAssertLessThanOrEqual(name.count, 255)
        }
    }
}

// MARK: - Doubles

/// Keeps challenges in memory and remembers which rooms' downloads were
/// thrown away.
private final class MemoryChallengeRepository: ChallengeRepository {
    private var challenges: [Challenge] = []
    private var templates: [ChallengeTemplate] = []
    func loadChallenges() -> [Challenge] { challenges }
    func saveChallenges(_ challenges: [Challenge]) { self.challenges = challenges }
    func loadTemplates() -> [ChallengeTemplate] { templates }
    func saveTemplates(_ templates: [ChallengeTemplate]) { self.templates = templates }
}

private final class RecordingClipFileStore: ClipFileStore {
    private(set) var deletedRemoteCaches: [String] = []

    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? { "day\(day).mov" }

    func clipURL(fileName: String, challengeID: UUID) -> URL {
        URL(fileURLWithPath: "/tmp/clips/\(challengeID.uuidString)/\(fileName)")
    }

    func deleteClips(challengeID: UUID) {}

    func remoteCacheDir(roomCode: String) -> URL {
        URL(fileURLWithPath: "/tmp/room/\(roomCode)", isDirectory: true)
    }

    func deleteRemoteCache(roomCode: String) { deletedRemoteCaches.append(roomCode) }

    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {}
}
