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
    private var account: AccountStore!

    override func setUp() {
        super.setUp()
        writes = []
        writeFails = false
        fetched = []
        fetchFails = false
        UserDefaults.standard.removeObject(forKey: RoomSyncService.publishedProfilesKey)
        account = AccountStore()
        account.signInAsTester(named: "Guest")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "account.v1")
        UserDefaults.standard.removeObject(forKey: RoomSyncService.publishedProfilesKey)
        account = nil
        super.tearDown()
    }

    private func transport() -> RoomSyncTransport {
        RoomSyncTransport(
            fetchClips: { _, _ in [] },
            fetchInteractions: { _ in ([], []) },
            uploadClip: { _, _, _, _, _, _, _, _ in },
            updateClipCaption: { _, _, _, _, _ in },
            setReaction: { _, _, _, _, _, _, _ in },
            postComment: { _, _, _, _, _, _, _ in },
            deleteComment: { _ in },
            saveMemberProfile: { [self] write in
                if writeFails { throw CloudKitService.CKServiceError.networkUnavailable }
                writes.append(write)
            },
            fetchMembers: { [self] _, _ in
                if fetchFails { throw CloudKitService.CKServiceError.networkUnavailable }
                return fetched
            })
    }

    private func store(rooms: [String], profile: MyRoomProfile?) -> ChallengeStore {
        let files = ProfileTestFileStore()
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
    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? { nil }
    func clipURL(fileName: String, challengeID: UUID) -> URL {
        URL(fileURLWithPath: "/tmp").appendingPathComponent(fileName)
    }
    func deleteClips(challengeID: UUID) {}
    func remoteCacheDir(roomCode: String) -> URL {
        URL(fileURLWithPath: "/tmp").appendingPathComponent(roomCode)
    }
    func deleteRemoteCache(roomCode: String) {}
    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {}
}
