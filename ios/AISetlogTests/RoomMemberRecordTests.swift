import XCTest
@testable import AISetlog

/// Joining a room by code leaves a `Member` record behind — once, under a
/// name that doesn't change, and never at the cost of the join itself.
/// CloudKit is stood in for by a transport that keeps records by name, the
/// way the public database does.
@MainActor
final class RoomMemberRecordTests: XCTestCase {
    private struct Member: Equatable {
        let code: String
        let userID: String
        let displayName: String
    }

    private var members: [String: Member] = [:]
    private var memberWrites = 0
    private var memberFails = false
    private var account: AccountStore!

    override func setUp() {
        super.setUp()
        members = [:]
        memberWrites = 0
        memberFails = false
        account = AccountStore()
        account.signInAsTester(named: "Guest")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "account.v1")
        account = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func room(_ code: String) -> CloudKitService.RemoteRoom {
        CloudKitService.RemoteRoom(
            code: code, title: "A perfect day",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            ownerID: "owner-1", ownerName: "Leo",
            mode: .oneDay, clipLength: .tiny, orientation: .portrait,
            cameraStyle: nil, templateName: nil,
            momentTitles: ["Morning", "Noon", "Night"])
    }

    private func transport(rooms: Set<String>) -> RoomSyncTransport {
        RoomSyncTransport(
            fetchClips: { _, _ in [] },
            fetchInteractions: { _ in ([], []) },
            uploadClip: { _, _, _, _, _, _, _, _ in },
            updateClipCaption: { _, _, _, _, _ in },
            setReaction: { _, _, _, _, _, _, _ in },
            postComment: { _, _, _, _, _, _, _ in },
            deleteComment: { _ in },
            fetchRoom: { [self] code in
                guard rooms.contains(code) else { throw CloudKitService.CKServiceError.roomNotFound }
                return room(code)
            },
            saveMember: { [self] code, userID, name, _ in
                memberWrites += 1
                if memberFails { throw CloudKitService.CKServiceError.networkUnavailable }
                members[CloudKitService.memberRecordName(code: code, authorID: userID)] =
                    Member(code: code, userID: userID, displayName: name)
            })
    }

    private func store(rooms: Set<String> = ["KPADC7"]) -> ChallengeStore {
        let files = MemberTestFileStore()
        let store = ChallengeStore(
            repository: MemberTestRepository(), fileStore: files,
            roomSync: RoomSyncService(fileStore: files, transport: transport(rooms: rooms)),
            effects: .isolatedButAllowingRooms)
        store.account = account
        return store
    }

    // MARK: - Tests

    func testJoiningWritesOneMemberRecord() async throws {
        let store = store()
        let me = try XCTUnwrap(account.account)

        let joined = try await store.joinRoom(code: "kp-adc7")

        XCTAssertEqual(joined.roomCode, "KPADC7")
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(
            members[CloudKitService.memberRecordName(code: "KPADC7", authorID: me.id)],
            Member(code: "KPADC7", userID: me.id, displayName: "Guest"))
    }

    func testJoiningAgainDoesNotAddASecondRecord() async throws {
        let store = store()
        let first = try await store.joinRoom(code: "KPADC7")
        // A room already on this phone opens without another write.
        _ = try await store.joinRoom(code: "KPADC7")
        XCTAssertEqual(memberWrites, 1)

        // Gone from this phone and joined again (a reinstall, a second device):
        // the write lands on the same record.
        store.challenges.removeAll { $0.id == first.id }
        _ = try await store.joinRoom(code: "KPADC7")
        XCTAssertEqual(memberWrites, 2)
        XCTAssertEqual(members.count, 1, "joining again must rewrite, not add: \(members.keys)")
    }

    func testAFailedMemberWriteStillJoinsTheRoom() async throws {
        memberFails = true
        let store = store()

        let joined = try await store.joinRoom(code: "KPADC7")

        XCTAssertEqual(memberWrites, 1, "the write should have been tried")
        XCTAssertTrue(members.isEmpty)
        XCTAssertEqual(store.challenges.map(\.id), [joined.id])
    }

    func testAJoinThatFindsNoRoomWritesNothing() async {
        let store = store(rooms: [])
        do {
            _ = try await store.joinRoom(code: "KPADC7")
            XCTFail("there is no such room")
        } catch CloudKitService.CKServiceError.roomNotFound {
        } catch {
            XCTFail("wrong error: \(error)")
        }
        XCTAssertEqual(memberWrites, 0)
        XCTAssertTrue(store.challenges.isEmpty)
    }

    func testALocalDemoRoomRefusesMemberWrites() async throws {
        let source = LocalRoomSyncSource(code: "LOCAL", clips: [])
        let transport = source.transport
        do {
            try await transport.saveMember("LOCAL", "me", "Me", .now)
            XCTFail("a demo room must not claim a member was saved")
        } catch LocalRoomSyncSource.Failure.readOnly {}
        do {
            _ = try await transport.fetchRoom("LOCAL")
            XCTFail("a demo room is not joined by code")
        } catch LocalRoomSyncSource.Failure.readOnly {}

        // And through the service: logged, swallowed, nothing thrown.
        let service = RoomSyncService(fileStore: MemberTestFileStore(), transport: transport)
        await service.recordMembership(code: "LOCAL", authorID: "me", displayName: "Me")

        source.close()
        do {
            try await transport.saveMember("LOCAL", "me", "Me", .now)
            XCTFail("a closed demo room must reject late writes")
        } catch LocalRoomSyncSource.Failure.closed {}
    }

    func testTheRecordNameIsTheCodeAndTheAuthor() {
        XCTAssertEqual(
            CloudKitService.memberRecordName(code: "KPADC7", authorID: "abc.123"),
            "KPADC7_abc.123")
    }
}

private extension ChallengeStoreEffects {
    /// Rooms allowed, everything else on this machine left alone.
    static var isolatedButAllowingRooms: ChallengeStoreEffects {
        ChallengeStoreEffects(
            allowsCloudRoomManagement: true,
            reconcileReminders: { _ in },
            reconcileSubscriptions: { _ in },
            resetNotificationPreferences: {})
    }
}

private final class MemberTestRepository: ChallengeRepository {
    private var challenges: [Challenge] = []
    func loadChallenges() -> [Challenge] { challenges }
    func saveChallenges(_ challenges: [Challenge]) { self.challenges = challenges }
}

private final class MemberTestFileStore: ClipFileStore {
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
