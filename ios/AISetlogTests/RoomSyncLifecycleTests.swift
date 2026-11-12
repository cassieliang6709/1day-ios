import XCTest
@testable import AISetlog

@MainActor
final class RoomSyncLifecycleTests: XCTestCase {
    private var directory: URL!
    private var files: LifecycleClipFiles!
    private var account: AccountStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        files = LifecycleClipFiles(root: directory)
        account = AccountStore()
        account.signInAsTester(named: "First")
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "account.v1")
        UserDefaults.standard.removeObject(forKey: RoomSyncService.publishedProfilesKey)
        UserDefaults.standard.removeObject(forKey: RoomSyncService.pendingRoomTitlesKey)
        try FileManager.default.removeItem(at: directory)
        account = nil
        files = nil
    }

    private func transport() -> RoomSyncTransport {
        RoomSyncTransport(
            fetchClips: { _, _ in [] }, fetchInteractions: { _ in ([], []) },
            uploadClip: { _, _, _, _, _, _, _, _ in },
            updateClipCaption: { _, _, _, _, _ in },
            setReaction: { _, _, _, _, _, _, _ in },
            postComment: { _, _, _, _, _, _, _ in }, deleteComment: { _ in })
    }

    private func store(transport: RoomSyncTransport) -> ChallengeStore {
        let service = RoomSyncService(fileStore: files, transport: transport)
        let store = ChallengeStore(
            repository: LifecycleRepository(), fileStore: files, roomSync: service,
            effects: ChallengeStoreEffects(allowsCloudRoomManagement: true,
                reconcileReminders: { _ in }, reconcileSubscriptions: { _ in },
                resetNotificationPreferences: {}))
        store.account = account
        return store
    }

    private func remoteRoom(_ code: String) -> CloudKitService.RemoteRoom {
        .init(code: code, title: code, startDate: Date(timeIntervalSince1970: 1),
              ownerID: "owner", ownerName: "Friend", mode: .oneDay, clipLength: .tiny,
              orientation: .portrait, cameraStyle: nil, templateName: nil, momentTitles: nil)
    }

    func testClearingRoomRejectsALateClipResponse() async {
        let response = HeldResponse<[CloudKitService.RemoteClip]>()
        var boundary = transport()
        boundary.fetchClips = { _, _ in await response.wait() }
        let service = RoomSyncService(fileStore: files, transport: boundary)
        let pull = Task { await service.syncClips(code: "AAAAAA") }
        await fulfillment(of: [response.started], timeout: 2)
        service.clearRoom("AAAAAA")
        response.resume([.init(id: "clip", day: 1, authorID: "first", authorName: "First",
                               recordedAt: .now, localURL: directory.appendingPathComponent("take.mov"),
                               overlayText: nil)])
        let result = await pull.value
        XCTAssertNil(result)
        XCTAssertNil(service.remoteClips["AAAAAA"])
        XCTAssertTrue(service.syncing.isEmpty)
    }

    func testClearingRoomRejectsALateRosterAndDoesNotRecreateItsCache() async {
        let response = HeldResponse<[CloudKitService.RemoteMember]>()
        var boundary = transport()
        boundary.fetchMembers = { _, _ in await response.wait() }
        let service = RoomSyncService(fileStore: files, transport: boundary)
        let pull = Task { await service.syncMembers(code: "AAAAAA") }
        await fulfillment(of: [response.started], timeout: 2)
        service.clearRoom("AAAAAA")
        response.resume([.init(userID: "first", displayName: "First", avatarURL: nil,
                               moodKind: nil, moodDay: nil, roomTitle: nil, roomTitleAt: nil)])
        await pull.value
        XCTAssertNil(service.remoteMembers["AAAAAA"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.remoteCacheDir(roomCode: "AAAAAA").path))
    }

    func testSigningOutStopsTheRemainingRoomSyncSteps() async {
        let response = HeldResponse<[CloudKitService.RemoteMember]>()
        let interactions = HeldResponse<(
            reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment])>()
        var clipRequests = 0
        var interactionRequests = 0
        var boundary = transport()
        boundary.fetchMembers = { _, _ in await response.wait() }
        boundary.fetchClips = { _, _ in clipRequests += 1; return [] }
        boundary.fetchInteractions = { _ in
            interactionRequests += 1
            return await interactions.wait()
        }
        let store = store(transport: boundary)
        let room = Challenge(id: UUID(), title: "Room", startDate: .now,
                             cards: [DayCard(day: 1)], roomCode: "AAAAAA")
        store.challenges = [room]
        let sync = Task { await store.syncRoom(room.id) }
        await fulfillment(of: [response.started, interactions.started], timeout: 2)
        store.signOut()
        response.resume([])
        interactions.resume(([], [.init(
            id: UUID().uuidString, day: 1, text: "Old account",
            authorID: "friend", authorName: "Friend", targetAuthorID: "first", createdAt: .now)]))
        await sync.value
        XCTAssertEqual(clipRequests, 0)
        XCTAssertEqual(interactionRequests, 1, "Interactions now start before media, but must not land after sign-out")
        XCTAssertNil(store.roomSync.remoteClips["AAAAAA"])
        XCTAssertNil(store.roomSync.remoteComments["AAAAAA"])
        XCTAssertNil(store.roomSync.remoteReactions["AAAAAA"])
    }

    func testInteractionsAppearBeforeTheRoomsVideoDownloadCompletes() async {
        let media = HeldResponse<[CloudKitService.RemoteClip]>()
        let fetchedInteractions = expectation(description: "Interactions fetched while video is held")
        var boundary = transport()
        boundary.fetchMembers = { _, _ in [] }
        boundary.fetchClips = { _, _ in await media.wait() }
        let comment = CloudKitService.RemoteComment(
            id: UUID().uuidString, day: 1, text: "Already here",
            authorID: "friend", authorName: "Friend", targetAuthorID: account.account!.id, createdAt: .now)
        boundary.fetchInteractions = { _ in
            fetchedInteractions.fulfill()
            return ([], [comment])
        }
        let store = store(transport: boundary)
        let room = Challenge(id: UUID(), title: "Room", startDate: .now,
                             cards: [DayCard(day: 1)], roomCode: "AAAAAA")
        store.challenges = [room]
        let sync = Task { await store.syncRoom(room.id) }
        await fulfillment(of: [media.started, fetchedInteractions], timeout: 2)
        // The media response is still suspended; no timing or fast-network assumption.
        XCTAssertEqual(store.roomSync.remoteComments["AAAAAA"]?.first?.text, "Already here")
        XCTAssertEqual(store.challenge(room.id)?.cards.first?.comments.first?.text, "Already here")
        media.resume([])
        await sync.value
    }

    func testOlderInteractionResponseCannotReplaceANewerRefresh() async {
        typealias Interactions = (
            reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment])
        let first = HeldResponse<Interactions>()
        let second = HeldResponse<Interactions>()
        var count = 0
        var boundary = transport()
        boundary.fetchMembers = { _, _ in [] }
        boundary.fetchInteractions = { _ in
            count += 1
            return count == 1 ? await first.wait() : await second.wait()
        }
        let store = store(transport: boundary)
        let room = Challenge(id: UUID(), title: "Room", startDate: .now,
                             cards: [DayCard(day: 1)], roomCode: "AAAAAA")
        store.challenges = [room]
        let old = Task { await store.syncRoom(room.id) }
        await fulfillment(of: [first.started], timeout: 2)
        let new = Task { await store.syncRoom(room.id) }
        await fulfillment(of: [second.started], timeout: 2)
        func comments(_ text: String) -> Interactions {
            ([], [.init(id: UUID().uuidString, day: 1, text: text,
                        authorID: "friend", authorName: "Friend", targetAuthorID: account.account!.id,
                        createdAt: .now)])
        }
        second.resume(comments("Newer"))
        await new.value
        first.resume(comments("Older"))
        await old.value
        XCTAssertEqual(store.roomSync.remoteComments["AAAAAA"]?.first?.text, "Newer")
        XCTAssertEqual(store.challenge(room.id)?.cards.first?.comments.first?.text, "Newer")
    }

    func testALateRestoreCannotAdoptThePreviousAccountsRoomsOrProfile() async {
        let response = HeldResponse<CloudKitService.MyRooms>()
        var boundary = transport()
        boundary.findMyRooms = { _ in await response.wait() }
        let store = store(transport: boundary)
        var adoptedAvatar: URL?
        store.adoptAvatar = { adoptedAvatar = $0 }
        let restore = Task { await store.restoreMyRooms() }
        await fulfillment(of: [response.started], timeout: 2)
        store.signOut()
        account.signInAsTester(named: "Second")
        response.resume(.init(memberCodes: ["OLDONE"], owned: [remoteRoom("OLDONE")],
                              displayName: "First", avatarFile: directory.appendingPathComponent("first.png")))
        await restore.value
        XCTAssertTrue(store.challenges.isEmpty)
        XCTAssertNil(adoptedAvatar)
        XCTAssertEqual(account.account?.displayName, "Second")
    }

    func testSixMembersIncludeUnnamedPeopleAndKeepDistinctIdentities() {
        let store = store(transport: transport())
        store.account = nil
        let room = Challenge(id: UUID(), title: "Room", startDate: .now, cards: [DayCard(day: 1)],
                             roomCode: "AAAAAA", ownerName: "Alex", ownerID: "person-0")
        store.challenges = [room]
        let members = ["Alex", "", "Alex", "", "Bo", "Di"].enumerated().map {
            CloudKitService.RemoteMember(userID: "person-\($0.offset)", displayName: $0.element,
                                          avatarURL: nil, moodKind: nil, moodDay: nil)
        }
        store.roomSync.remoteMembers["AAAAAA"] = Dictionary(uniqueKeysWithValues: members.map { ($0.userID, $0) })
        let roster = store.members(for: room.id)
        XCTAssertEqual(roster.count, 6)
        XCTAssertEqual(roster.filter { $0.name.isEmpty }.count, 2)
        XCTAssertEqual(Set(roster.map(\.id)).count, 6)
        XCTAssertEqual(RoomAvatarLayout(memberCount: roster.count).centers.count, 6)
    }

    func testALateJoinAfterSignOutDoesNotInsertARoomOrPublishMembership() async {
        let response = HeldResponse<CloudKitService.RemoteRoom>()
        var membershipWrites = 0
        var boundary = transport()
        boundary.fetchRoom = { _ in await response.wait() }
        boundary.saveMember = { _, _, _, _ in membershipWrites += 1 }
        let store = store(transport: boundary)
        let join = Task { try await store.joinRoom(code: "AAAAAA") }
        await fulfillment(of: [response.started], timeout: 2)
        store.signOut()
        response.resume(remoteRoom("AAAAAA"))
        do { _ = try await join.value; XCTFail("An obsolete session must not finish joining") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(store.challenges.isEmpty)
        XCTAssertEqual(membershipWrites, 0)
    }

    func testConcurrentJoinsOfTheSameRoomKeepOneLocalIdentity() async throws {
        let firstResponse = HeldResponse<CloudKitService.RemoteRoom>()
        let secondResponse = HeldResponse<CloudKitService.RemoteRoom>()
        var requests = 0
        var membershipWrites = 0
        var boundary = transport()
        boundary.fetchRoom = { _ in
            requests += 1
            return requests == 1 ? await firstResponse.wait() : await secondResponse.wait()
        }
        boundary.saveMember = { _, _, _, _ in membershipWrites += 1 }
        let store = store(transport: boundary)
        let first = Task { try await store.joinRoom(code: "AAAAAA") }
        await fulfillment(of: [firstResponse.started], timeout: 2)
        let second = Task { try await store.joinRoom(code: "AAAAAA") }
        await fulfillment(of: [secondResponse.started], timeout: 2)
        firstResponse.resume(remoteRoom("AAAAAA"))
        let joined = try await first.value
        secondResponse.resume(remoteRoom("AAAAAA"))
        let joinedAgain = try await second.value
        XCTAssertEqual(joined.id, joinedAgain.id)
        XCTAssertEqual(store.challenges.count, 1)
        XCTAssertEqual(membershipWrites, 1)
    }

    func testNewAccountRestorationCanFinishWhileTheOldAccountRequestWaits() async {
        let response = HeldResponse<CloudKitService.MyRooms>()
        let firstID = account.account!.id
        var requested: [String] = []
        var boundary = transport()
        boundary.findMyRooms = { [self] userID in
            requested.append(userID)
            if userID == firstID { return await response.wait() }
            return .init(memberCodes: ["NEWONE"], owned: [remoteRoom("NEWONE")])
        }
        let store = store(transport: boundary)
        let oldRestore = Task { await store.restoreMyRooms() }
        await fulfillment(of: [response.started], timeout: 2)
        store.signOut()
        account.signInAsTester(named: "Second")
        await store.restoreMyRooms()
        response.resume(.init(memberCodes: ["OLDONE"], owned: [remoteRoom("OLDONE")]))
        await oldRestore.value
        XCTAssertEqual(requested.count, 2)
        XCTAssertEqual(store.challenges.compactMap(\.roomCode), ["NEWONE"])
    }
}

final class NotificationInboxLifecycleTests: XCTestCase {
    func testInspectingARouteDoesNotConsumeItBeforeTheCameraCanLeave() {
        let route = NotificationRecordRoute(challengeID: UUID(), day: 2)
        NotificationRouteInbox.enqueue(route)
        XCTAssertEqual(NotificationRouteInbox.peek(), route)
        XCTAssertEqual(NotificationRouteInbox.peek(), route)
        XCTAssertEqual(NotificationRouteInbox.consume(), route)
        XCTAssertNil(NotificationRouteInbox.peek())
    }
}

@MainActor
private final class HeldResponse<Value> {
    let started = XCTestExpectation(description: "Request reached the remote boundary")
    private var continuation: CheckedContinuation<Value, Never>?

    func wait() async -> Value {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }

    func resume(_ value: Value) {
        continuation!.resume(returning: value)
        continuation = nil
    }
}

private final class LifecycleRepository: ChallengeRepository {
    func loadChallenges() -> [Challenge] { [] }
    func saveChallenges(_ challenges: [Challenge]) {}
}

private final class LifecycleClipFiles: ClipFileStore {
    let root: URL
    init(root: URL) { self.root = root }
    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? { nil }
    func clipURL(fileName: String, challengeID: UUID) -> URL { root.appendingPathComponent(fileName) }
    func deleteClips(challengeID: UUID) {}
    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {}
    func remoteCacheDir(roomCode: String) -> URL { root.appendingPathComponent(roomCode) }
    func deleteRemoteCache(roomCode: String) {
        try? FileManager.default.removeItem(at: remoteCacheDir(roomCode: roomCode))
    }
}
