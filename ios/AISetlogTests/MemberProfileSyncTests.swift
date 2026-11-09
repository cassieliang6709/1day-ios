import XCTest
@testable import AISetlog

/// My avatar and today's mood face go to my `Member` record in every room I'm
/// in, once per change, and never block anything when CloudKit says no. A
/// friend's mood shows only on the day they picked it. The mood's note is
/// never part of what's sent.
@MainActor
final class MemberProfileSyncTests: XCTestCase {
    private var writes: [CloudKitService.MemberProfileWrite] = []
    private var writeFails = false
    private var fetched: [CloudKitService.RemoteMember] = []
    private var fetchFails = false
    private var titleWrites: [(code: String, title: String, at: Date)] = []
    private var titleWriteFails = false
    private var deleted: Set<String> = []
    private var calls: [String] = []
    private var myRooms: CloudKitService.MyRooms?
    private var account: AccountStore!

    override func setUp() {
        super.setUp()
        writes = []
        writeFails = false
        fetched = []
        fetchFails = false
        titleWrites = []
        titleWriteFails = false
        deleted = []
        calls = []
        myRooms = nil
        UserDefaults.standard.removeObject(forKey: RoomSyncService.publishedProfilesKey)
        UserDefaults.standard.removeObject(forKey: RoomSyncService.pendingRoomTitlesKey)
        account = AccountStore()
        account.signInAsTester(named: "Guest")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "account.v1")
        UserDefaults.standard.removeObject(forKey: RoomSyncService.publishedProfilesKey)
        UserDefaults.standard.removeObject(forKey: RoomSyncService.pendingRoomTitlesKey)
        account = nil
        super.tearDown()
    }

    private func transport() -> RoomSyncTransport {
        RoomSyncTransport(
            fetchClips: { [self] _, _ in
                calls.append("clips")
                return []
            },
            fetchInteractions: { _ in ([], []) },
            uploadClip: { _, _, _, _, _, _, _, _ in },
            updateClipCaption: { _, _, _, _, _ in },
            setReaction: { _, _, _, _, _, _, _ in },
            postComment: { _, _, _, _, _, _, _ in },
            deleteComment: { _ in },
            fetchRoom: { code in
                CloudKitService.RemoteRoom(
                    code: code, title: "房间", startDate: .now, ownerID: "owner-1", ownerName: "Leo",
                    mode: .oneDay, clipLength: .tiny, orientation: .portrait,
                    cameraStyle: nil, templateName: nil, momentTitles: nil)
            },
            saveMember: { _, _, _, _ in },
            saveMemberProfile: { [self] write in
                if writeFails { throw CloudKitService.CKServiceError.networkUnavailable }
                writes.append(write)
            },
            saveRoomTitle: { [self] code, _, _, title, at in
                if titleWriteFails { throw CloudKitService.CKServiceError.networkUnavailable }
                titleWrites.append((code, title, at))
            },
            myRecordNames: { code, author in
                ["\(code)_\(author)", "clip-\(author)-1", "comment-\(author)"]
            },
            deleteRecords: { [self] names in
                deleted.formUnion(names)
                return names
            },
            fetchMembers: { [self] _, _ in
                calls.append("members")
                if fetchFails { throw CloudKitService.CKServiceError.networkUnavailable }
                return fetched
            },
            findMyRooms: { [self] _ in
                guard let myRooms else { throw CloudKitService.CKServiceError.networkUnavailable }
                return myRooms
            })
    }

    private func store(
        rooms: [String], profile: MyRoomProfile?, files: ProfileTestFileStore = ProfileTestFileStore()
    ) -> ChallengeStore {
        let store = ChallengeStore(
            repository: ProfileTestRepository(), fileStore: files,
            roomSync: RoomSyncService(fileStore: files, transport: transport()),
            effects: ChallengeStoreEffects(
                allowsCloudRoomManagement: true,
                reconcileReminders: { _ in },
                reconcileSubscriptions: { _ in },
                resetNotificationPreferences: {}))
        store.account = account
        store.myRoomProfile = { profile }
        store.challenges = rooms.map { code in
            Challenge(id: UUID(), title: code, startDate: .now, cards: [DayCard(day: 1)],
                      roomCode: code, ownerName: "Leo", ownerID: "owner-1")
        }
        return store
    }

    private let avatar = URL(fileURLWithPath: "/tmp/avatar-test.png")
    private let picked = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: - Publishing

    func testMoodAndAvatarGoToEveryRoomImIn() async {
        let profile = MyRoomProfile(avatarURL: avatar, avatarVersion: picked, mood: .happy, moodAt: picked)
        let store = store(rooms: ["AAAAAA", "BBBBBB"], profile: profile)

        await store.publishMyProfileToAllRooms()

        XCTAssertEqual(Set(writes.map(\.code)), ["AAAAAA", "BBBBBB"])
        for write in writes {
            XCTAssertEqual(write.authorID, account.account?.id)
            XCTAssertEqual(write.moodKind, "happy")
            XCTAssertEqual(write.moodDay, picked)
            XCTAssertEqual(write.avatarURL, avatar)
        }
    }

    func testTheSameProfileIsNotSentTwice() async {
        let profile = MyRoomProfile(avatarURL: avatar, avatarVersion: picked, mood: .calm, moodAt: picked)
        let store = store(rooms: ["AAAAAA"], profile: profile)
        await store.publishMyProfileToAllRooms()
        await store.publishMyProfileToAllRooms()
        XCTAssertEqual(writes.count, 1)
    }

    func testChangingTheMoodSendsItAgain() async {
        var profile = MyRoomProfile(avatarURL: nil, avatarVersion: nil, mood: .calm, moodAt: picked)
        let store = store(rooms: ["AAAAAA"], profile: profile)
        await store.publishMyProfileToAllRooms()
        profile.mood = .tired
        store.myRoomProfile = { profile }
        await store.publishMyProfileToAllRooms()
        XCTAssertEqual(writes.map(\.moodKind), ["calm", "tired"])
    }

    func testAMoodChangeDoesNotUploadTheSameAvatarAgain() async {
        var profile = MyRoomProfile(avatarURL: avatar, avatarVersion: picked, mood: .calm, moodAt: picked)
        let store = store(rooms: ["AAAAAA"], profile: profile)
        await store.publishMyProfileToAllRooms()
        profile.mood = .happy
        store.myRoomProfile = { profile }
        await store.publishMyProfileToAllRooms()
        profile.avatarVersion = picked.addingTimeInterval(60)
        store.myRoomProfile = { profile }
        await store.publishMyProfileToAllRooms()
        XCTAssertEqual(writes.map(\.avatarURL), [avatar, nil, avatar])
    }

    func testAFailedWriteIsTriedAgainNextTime() async {
        writeFails = true
        let profile = MyRoomProfile(avatarURL: nil, avatarVersion: nil, mood: .sad, moodAt: picked)
        let store = store(rooms: ["AAAAAA"], profile: profile)
        await store.publishMyProfileToAllRooms()
        XCTAssertTrue(writes.isEmpty)

        writeFails = false
        await store.publishMyProfileToAllRooms()
        XCTAssertEqual(writes.count, 1, "a write that failed must not count as sent")
    }

    func testNoAvatarAndNoMoodSendsNothing() async {
        let store = store(rooms: ["AAAAAA"], profile: MyRoomProfile())
        await store.publishMyProfileToAllRooms()
        XCTAssertTrue(writes.isEmpty)
    }

    func testOnlyTheMoodFaceIsSentNeverTheNote() async throws {
        // The profile is built from a mood entry that has a note; nothing in
        // the write can carry it.
        let entry = MoodEntry(day: MoodDay.key(for: picked), mood: .angry,
                              note: "secret diary line", updatedAt: picked)
        let profile = MyRoomProfile.make(avatar: AvatarStore(fileURL: nil), today: entry)
        let store = store(rooms: ["AAAAAA"], profile: profile)
        await store.publishMyProfileToAllRooms()
        let write = try XCTUnwrap(writes.first)
        XCTAssertEqual(write.moodKind, "angry")
        XCTAssertFalse(String(describing: write).contains("secret"))
    }

    func testADemoStoreNeverWrites() async {
        let profile = MyRoomProfile(avatarURL: nil, avatarVersion: nil, mood: .happy, moodAt: picked)
        let store = store(rooms: ["AAAAAA"], profile: profile)
        let isolated = ChallengeStore(
            repository: ProfileTestRepository(), fileStore: ProfileTestFileStore(),
            roomSync: store.roomSync, effects: .isolated)
        isolated.account = account
        isolated.myRoomProfile = { profile }
        isolated.challenges = store.challenges
        await isolated.publishMyProfileToAllRooms()
        XCTAssertTrue(writes.isEmpty)
    }

    // MARK: - Room name

    func testRenamingARoomChangesItHereAndSendsIt() async {
        let store = store(rooms: ["AAAAAA"], profile: nil)
        await store.renameRoom(store.challenges[0].id, to: "  周末小队 ")
        XCTAssertEqual(store.challenges[0].title, "周末小队")
        XCTAssertEqual(titleWrites.map(\.code), ["AAAAAA"])
        XCTAssertEqual(titleWrites.map(\.title), ["周末小队"])
    }

    func testTheNewestNameInTheRoomWinsOnSync() async {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        fetched = [
            .init(userID: "a", displayName: "A", avatarURL: nil, moodKind: nil, moodDay: nil,
                  roomTitle: "旧名字", roomTitleAt: old),
            .init(userID: "b", displayName: "B", avatarURL: nil, moodKind: nil, moodDay: nil,
                  roomTitle: "新名字", roomTitleAt: new),
            .init(userID: "c", displayName: "C", avatarURL: nil, moodKind: nil, moodDay: nil),
        ]
        let store = store(rooms: ["AAAAAA"], profile: nil)
        await store.syncRoom(store.challenges[0].id)
        XCTAssertEqual(store.challenges[0].title, "新名字")
    }

    func testNobodyRenamedKeepsTheName() async {
        fetched = [.init(userID: "a", displayName: "A", avatarURL: nil, moodKind: nil, moodDay: nil)]
        let store = store(rooms: ["AAAAAA"], profile: nil)
        await store.syncRoom(store.challenges[0].id)
        XCTAssertEqual(store.challenges[0].title, "AAAAAA")
    }

    func testARenameThatFailedKeepsMyNameAndIsSentNextSync() async {
        titleWriteFails = true
        fetched = [.init(userID: "a", displayName: "A", avatarURL: nil, moodKind: nil, moodDay: nil,
                         roomTitle: "朋友起的", roomTitleAt: .distantPast)]
        let store = store(rooms: ["AAAAAA"], profile: nil)
        let id = store.challenges[0].id
        await store.renameRoom(id, to: "我起的")
        await store.syncRoom(id)
        XCTAssertEqual(store.challenges[0].title, "我起的", "an older name must not undo mine while it's on its way")
        XCTAssertTrue(titleWrites.isEmpty)

        titleWriteFails = false
        await store.syncRoom(id)
        XCTAssertEqual(titleWrites.map(\.title), ["我起的"])
        XCTAssertTrue(store.roomSync.pendingRoomTitles.isEmpty)
    }

    func testADemoStoreRenamesOnlyHere() async {
        let store = store(rooms: ["AAAAAA"], profile: nil)
        let isolated = ChallengeStore(
            repository: ProfileTestRepository(), fileStore: ProfileTestFileStore(),
            roomSync: store.roomSync, effects: .isolated)
        isolated.account = account
        isolated.challenges = store.challenges
        await isolated.renameRoom(isolated.challenges[0].id, to: "演示")
        XCTAssertEqual(isolated.challenges[0].title, "演示")
        XCTAssertTrue(titleWrites.isEmpty)
    }

    // MARK: - Leaving

    func testLeavingARoomDeletesMyRecordsForEveryone() async throws {
        let store = store(rooms: ["AAAAAA"], profile: nil)
        let me = try XCTUnwrap(account.account?.id)
        store.delete(store.challenges[0].id)
        XCTAssertTrue(store.challenges.isEmpty, "gone here at once")
        for _ in 0..<50 where deleted.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(deleted, ["AAAAAA_\(me)", "clip-\(me)-1", "comment-\(me)"])
    }

    func testDeletingMyOwnStoryTouchesNoRoom() async throws {
        let store = store(rooms: [], profile: nil)
        let story = store.create(title: "我的", mode: .oneDay, clipLength: .tiny,
                                 orientation: .portrait, templateName: nil, momentTitles: ["a"])
        store.delete(story.id)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(deleted.isEmpty)
    }

    // MARK: - Room size

    func testTheGridFollowsTheHeadCount() {
        XCTAssertTrue(RoomFrames.grid(for: 1) == (1, 1))
        XCTAssertTrue(RoomFrames.grid(for: 2) == (2, 1), "two people: side by side")
        XCTAssertTrue(RoomFrames.grid(for: 3) == (1, 3))
        XCTAssertTrue(RoomFrames.grid(for: 4) == (2, 2))
        XCTAssertTrue(RoomFrames.grid(for: 5) == (2, 3), "five: six places, the last left empty")
        XCTAssertTrue(RoomFrames.grid(for: 6) == (2, 3))
    }

    private func person(_ id: String) -> CloudKitService.RemoteMember {
        .init(userID: id, displayName: id, avatarURL: nil, moodKind: nil, moodDay: nil)
    }

    func testAFullRoomTurnsTheSeventhPersonAway() async {
        fetched = (1...5).map { person("p\($0)") }   // plus the owner: six
        let store = store(rooms: [], profile: nil)
        do {
            _ = try await store.joinRoom(code: "ABCDEF")
            XCTFail("a seventh person must not get in")
        } catch {
            XCTAssertEqual(error as? CloudKitService.CKServiceError, .roomFull)
        }
        XCTAssertTrue(store.challenges.isEmpty)
    }

    func testARoomWithSpaceLetsMeIn() async throws {
        fetched = (1...4).map { person("p\($0)") }   // plus the owner: five
        let store = store(rooms: [], profile: nil)
        _ = try await store.joinRoom(code: "ABCDEF")
        XCTAssertEqual(store.challenges.first?.roomCode, "ABCDEF")
    }

    func testUnreadableMembersDoNotBlockAJoin() async throws {
        fetchFails = true
        let store = store(rooms: [], profile: nil)
        _ = try await store.joinRoom(code: "ABCDEF")
        XCTAssertEqual(store.challenges.count, 1)
    }

    func testSomebodyWhoJoinedButHasntFilmedIsInTheRoom() async {
        fetched = [person("quiet")]
        let store = store(rooms: ["AAAAAA"], profile: nil)
        await store.roomSync.syncMembers(code: "AAAAAA")
        let ids = store.members(for: store.challenges[0].id).map(\.id)
        XCTAssertTrue(ids.contains("quiet"))
    }

    // MARK: - Reading

    func testFriendsMoodShowsOnlyOnTheDayItWasPicked() async {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        fetched = [
            .init(userID: "a", displayName: "A", avatarURL: avatar, moodKind: "happy", moodDay: now),
            .init(userID: "b", displayName: "B", avatarURL: nil, moodKind: "sad", moodDay: yesterday),
            .init(userID: "c", displayName: "C", avatarURL: nil, moodKind: "unknown-mood", moodDay: now),
        ]
        let store = store(rooms: ["AAAAAA"], profile: nil)
        await store.roomSync.syncMembers(code: "AAAAAA")

        let profiles = store.memberProfiles(for: store.challenges[0].id, now: now)
        XCTAssertEqual(profiles["a"], MemberProfile(avatarURL: avatar, mood: .happy))
        XCTAssertEqual(profiles["b"]?.mood, nil, "yesterday's mood is over")
        XCTAssertEqual(profiles["c"]?.mood, nil, "a mood this build doesn't know is skipped")
    }

    func testAFailedFetchKeepsTheFacesWeHad() async {
        fetched = [.init(userID: "a", displayName: "A", avatarURL: avatar, moodKind: nil, moodDay: nil)]
        let store = store(rooms: ["AAAAAA"], profile: nil)
        await store.roomSync.syncMembers(code: "AAAAAA")
        fetchFails = true
        await store.roomSync.syncMembers(code: "AAAAAA")
        XCTAssertEqual(store.memberProfiles(for: store.challenges[0].id)["a"]?.avatarURL, avatar)
    }

    func testARoomAsksWhoIsInItBeforeDownloadingClips() async {
        fetched = [person("quiet")]
        let store = store(rooms: ["AAAAAA"], profile: nil)
        await store.syncRoom(store.challenges[0].id)
        XCTAssertEqual(calls.first, "members")
        XCTAssertTrue(calls.contains("clips"))
    }

    func testTheRosterIsBackRightAfterARelaunch() async throws {
        let files = ProfileTestFileStore()
        let avatarFile = files.remoteCacheDir(roomCode: "AAAAAA")
            .appendingPathComponent("members", isDirectory: true)
            .appendingPathComponent("avatar_a.png")
        try FileManager.default.createDirectory(
            at: avatarFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: avatarFile)
        fetched = [.init(userID: "a", displayName: "A", avatarURL: avatarFile, moodKind: nil, moodDay: nil)]
        await store(rooms: ["AAAAAA"], profile: nil, files: files).roomSync.syncMembers(code: "AAAAAA")

        // Next launch: a fresh service, and CloudKit not answering yet.
        fetchFails = true
        let relaunched = store(rooms: ["AAAAAA"], profile: nil, files: files)
        relaunched.roomSync.restoreCachedMembers(code: "AAAAAA")
        let id = relaunched.challenges[0].id
        XCTAssertTrue(relaunched.members(for: id).contains { $0.id == "a" && $0.name == "A" })
        XCTAssertEqual(relaunched.memberProfiles(for: id)["a"]?.avatarURL, avatarFile)
    }

    func testARestoredRosterNeverReplacesAFresherOne() async {
        let files = ProfileTestFileStore()
        fetched = [person("old")]
        let store = store(rooms: ["AAAAAA"], profile: nil, files: files)
        await store.roomSync.syncMembers(code: "AAAAAA")
        store.roomSync.remoteMembers["AAAAAA"] = [:]
        store.roomSync.restoreCachedMembers(code: "AAAAAA")
        XCTAssertEqual(store.roomSync.remoteMembers["AAAAAA"]?.isEmpty, true)
    }

    // MARK: - Restoring rooms

    private func ownedRoom(_ code: String, startedOn start: Date) -> CloudKitService.RemoteRoom {
        CloudKitService.RemoteRoom(
            code: code, title: "我的房间", startDate: start, ownerID: account.account!.id, ownerName: "Me",
            mode: .oneDay, clipLength: .tiny, orientation: .portrait,
            cameraStyle: nil, templateName: nil, momentTitles: nil)
    }

    /// A new phone: the rooms my `Member` records name come back, and one
    /// already here isn't added twice.
    func testRoomsIJoinedComeBackOnANewPhone() async {
        myRooms = .init(memberCodes: ["AAAAAA", "BBBBBB", "CCCCCC"], owned: [])
        let store = store(rooms: ["AAAAAA"], profile: nil)
        await store.restoreMyRooms()
        XCTAssertEqual(Set(store.challenges.compactMap(\.roomCode)), ["AAAAAA", "BBBBBB", "CCCCCC"])
        XCTAssertEqual(store.challenges.count, 3)
        await store.restoreMyRooms()
        XCTAssertEqual(store.challenges.count, 3, "a second pass adds nothing")
    }

    /// A room I made before owners got a `Member` record comes back through
    /// its owner ID; one I made later and then left (no record) stays gone.
    func testOwnedRoomsComeBackUnlessILeftThem() async {
        let before = ChallengeStore.ownerMemberRecordsSince.addingTimeInterval(-86_400)
        let after = ChallengeStore.ownerMemberRecordsSince.addingTimeInterval(86_400)
        myRooms = .init(
            memberCodes: ["KEPTNW"],
            owned: [ownedRoom("OLDONE", startedOn: before), ownedRoom("LEFTIT", startedOn: after),
                    ownedRoom("KEPTNW", startedOn: after)])
        let store = store(rooms: [], profile: nil)
        await store.restoreMyRooms()
        XCTAssertEqual(Set(store.challenges.compactMap(\.roomCode)), ["OLDONE", "KEPTNW"])
        XCTAssertEqual(store.challenges.first { $0.roomCode == "OLDONE" }?.title, "我的房间")
    }

    /// No answer from the cloud changes nothing — it never removes a room.
    func testAFailedLookupLeavesTheRoomListAlone() async {
        myRooms = nil
        let store = store(rooms: ["AAAAAA"], profile: nil)
        await store.restoreMyRooms()
        XCTAssertEqual(store.challenges.compactMap(\.roomCode), ["AAAAAA"])
    }

    // MARK: - Another account on this phone

    private func defaults() throws -> UserDefaults {
        let d = try XCTUnwrap(UserDefaults(suiteName: "AccountRoomsTests"))
        d.removePersistentDomain(forName: "AccountRoomsTests")
        return d
    }

    /// Someone else signs in: the last person's shared rooms and avatar leave
    /// this phone before anything syncs, so none of their takes go up under
    /// the new account. Personal stories stay.
    func testAnotherAccountDoesNotInheritTheLastPersonsRooms() async throws {
        let d = try defaults()
        d.set("someone-else", forKey: ChallengeStore.roomsAccountKey)
        myRooms = .init(memberCodes: [], owned: [])
        let store = store(rooms: ["AAAAAA"], profile: nil)
        store.challenges.append(Challenge(id: UUID(), title: "mine", startDate: .now, cards: [DayCard(day: 1)]))
        var forgot = false
        store.forgetAvatar = { forgot = true }
        await store.reconcileAccountRooms(defaults: d)
        XCTAssertEqual(store.challenges.map(\.title), ["mine"])
        XCTAssertTrue(forgot)
        XCTAssertEqual(d.string(forKey: ChallengeStore.roomsAccountKey), account.account?.id)
        d.removePersistentDomain(forName: "AccountRoomsTests")
    }

    /// The same person signing back in keeps everything, takes still
    /// waiting to upload included; so does a phone that never recorded whose
    /// rooms they were.
    func testTheSamePersonKeepsTheirRooms() async throws {
        let d = try defaults()
        myRooms = .init(memberCodes: [], owned: [])
        let store = store(rooms: ["AAAAAA"], profile: nil)
        var forgot = false
        store.forgetAvatar = { forgot = true }
        await store.reconcileAccountRooms(defaults: d)
        await store.reconcileAccountRooms(defaults: d)
        XCTAssertEqual(store.challenges.compactMap(\.roomCode), ["AAAAAA"])
        XCTAssertFalse(forgot)
        d.removePersistentDomain(forName: "AccountRoomsTests")
    }

    /// A new phone: no name from Apple, no avatar file. Both come back from
    /// my own `Member` records; a name I already have is never replaced.
    func testANewPhoneGetsMyNameAndAvatarBack() async {
        account.signInAsTester(named: "")
        myRooms = .init(memberCodes: [], owned: [], displayName: "Cassie", avatarFile: avatar)
        let store = store(rooms: [], profile: nil)
        var adopted: URL?
        store.adoptAvatar = { adopted = $0 }
        await store.restoreMyRooms()
        XCTAssertEqual(account.account?.displayName, "Cassie")
        XCTAssertEqual(adopted, avatar)

        account.rename(to: "Cass")
        await store.restoreMyRooms()
        XCTAssertEqual(account.account?.displayName, "Cass")
    }

    /// A take uploaded while its author had no name doesn't blank the name
    /// their `Member` record shows.
    func testANamelessTakeDoesNotBlankAMembersName() async {
        fetched = [.init(userID: "leo", displayName: "Leo", avatarURL: nil, moodKind: nil, moodDay: nil)]
        let store = store(rooms: ["AAAAAA"], profile: nil)
        await store.roomSync.syncMembers(code: "AAAAAA")
        store.roomSync.remoteClips["AAAAAA"] = [CloudKitService.RemoteClip(
            id: "x", day: 1, authorID: "leo", authorName: "", recordedAt: .now,
            localURL: avatar, overlayText: nil)]
        XCTAssertEqual(store.members(for: store.challenges[0].id).first { $0.id == "leo" }?.name, "Leo")
    }

    func testTheDefaultTransportNeverReachesCloudKitForProfiles() async {
        let bare = RoomSyncTransport(
            fetchClips: { _, _ in [] }, fetchInteractions: { _ in ([], []) },
            uploadClip: { _, _, _, _, _, _, _, _ in }, updateClipCaption: { _, _, _, _, _ in },
            setReaction: { _, _, _, _, _, _, _ in }, postComment: { _, _, _, _, _, _, _ in },
            deleteComment: { _ in })
        let service = RoomSyncService(fileStore: ProfileTestFileStore(), transport: bare)
        let sent = await service.publishProfile(
            .init(code: "AAAAAA", authorID: "me", displayName: "Me", avatarURL: nil,
                  moodKind: "happy", moodDay: .now),
            signature: "x")
        XCTAssertFalse(sent)
        await service.syncMembers(code: "AAAAAA")
        XCTAssertNil(service.remoteMembers["AAAAAA"])
    }

    func testAvatarFileNamesAreSafe() {
        XCTAssertEqual(CloudKitService.memberAvatarFileName(userID: "001234.abcd/ef"), "avatar_001234_abcd_ef.png")
    }

    // MARK: - Invite card

    func testTheInviteCardCarriesTheInvitersAvatar() {
        let room = Challenge(id: UUID(), title: "Day", startDate: .now, cards: [DayCard(day: 1)],
                             roomCode: "AAAAAA", ownerName: "Leo", ownerID: "owner-1")
        let content = RoomInviteCardContent(challenge: room, inviter: "Leo", inviterAvatarURL: avatar)
        XCTAssertEqual(content.inviterAvatarURL, avatar)
        XCTAssertNil(RoomInviteCardContent(title: "Day", code: "AAAAAA", inviter: "Leo").inviterAvatarURL)
    }
}

private final class ProfileTestRepository: ChallengeRepository {
    private var challenges: [Challenge] = []
    func loadChallenges() -> [Challenge] { challenges }
    func saveChallenges(_ challenges: [Challenge]) { self.challenges = challenges }
}

private final class ProfileTestFileStore: ClipFileStore {
    /// Its own folder per store, so a roster saved by one test is never
    /// restored by another.
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("profile-tests-\(UUID().uuidString)", isDirectory: true)
    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? { nil }
    func clipURL(fileName: String, challengeID: UUID) -> URL {
        URL(fileURLWithPath: "/tmp").appendingPathComponent(fileName)
    }
    func deleteClips(challengeID: UUID) {}
    func remoteCacheDir(roomCode: String) -> URL {
        root.appendingPathComponent(roomCode)
    }
    func deleteRemoteCache(roomCode: String) {}
    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {}
}
