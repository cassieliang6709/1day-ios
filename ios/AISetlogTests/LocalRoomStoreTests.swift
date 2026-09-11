import XCTest
@testable import AISetlog

@MainActor
final class LocalRoomStoreTests: XCTestCase {
    func testLivePolicyRoutesNotificationsOnlyWhenRoomSetChanges() throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        var reminderCalls = 0
        var subscriptionCalls = 0
        // Start with the actual live policy, replacing external calls with spies.
        var effects = ChallengeStoreEffects.live
        XCTAssertTrue(effects.allowsCloudRoomManagement)
        effects.reconcileReminders = { _ in reminderCalls += 1 }
        effects.reconcileSubscriptions = { _ in subscriptionCalls += 1 }
        let store = ChallengeStore(repository: files, fileStore: files, coverStore: files, effects: effects)
        XCTAssertEqual(reminderCalls, 1, "initial repository load reconciles reminders")
        let room = store.create(title: "Local story")
        XCTAssertEqual(reminderCalls, 2)
        XCTAssertEqual(subscriptionCalls, 0)
        store.challenges[0].roomCode = "ROOM"
        XCTAssertEqual(subscriptionCalls, 1)
        store.updatePlan(room.id, title: "Renamed", momentTitles: ["One"])
        XCTAssertEqual(subscriptionCalls, 1)
        store.delete(room.id)
        XCTAssertEqual(reminderCalls, 5)
        XCTAssertEqual(subscriptionCalls, 2)
    }

    func testIsolatedStoreRejectsAllDirectCloudManagementAndAccountWipe() async throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        let source = LocalRoomSyncSource(code: "LOCAL", clips: [])
        let sync = RoomSyncService(fileStore: files, transport: source.transport)
        let store = ChallengeStore(repository: files, fileStore: files, coverStore: files, roomSync: sync, effects: .isolated)
        let identity = AccountStore(localIdentity: .init(id: "local-a", displayName: "A"))
        store.account = identity
        let epoch = AccountStore.identityRevision
        let story = store.create(title: "Keep me")
        do { _ = try await store.createSharedRoom(title: "Never cloud"); XCTFail("must reject") }
        catch ChallengeStore.IsolationError.cloudRoomManagementDisabled { }
        do { _ = try await store.joinRoom(code: "KPADC7"); XCTFail("must reject") }
        catch ChallengeStore.IsolationError.cloudRoomManagementDisabled { }
        await store.deleteAccountAndAllData()
        XCTAssertEqual(store.challenges.map(\.id), [story.id])
        XCTAssertEqual(files.loadChallenges().map(\.id), [story.id])
        XCTAssertTrue(identity.isSignedIn)
        XCTAssertEqual(AccountStore.identityRevision, epoch)
        store.signOut()
        XCTAssertFalse(identity.isSignedIn)
        XCTAssertEqual(AccountStore.identityRevision, epoch)
    }

    func testIsolatedSevenDayCreateSaveAndReloadUsesRealStore() throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        func makeStore() -> ChallengeStore {
            let source = LocalRoomSyncSource(code: "LOCAL", clips: [])
            return ChallengeStore(repository: files, fileStore: files, coverStore: files,
                                  roomSync: RoomSyncService(fileStore: files, transport: source.transport), effects: .isolated)
        }
        let store = makeStore()
        let prompts = (1...7).map { "User text \($0)" }
        let story = store.create(title: "Seven", mode: .sevenDay, momentTitles: prompts)
        let input = files.root.appendingPathComponent("input.mov")
        try Data("isolated fixture".utf8).write(to: input)
        store.saveClip(from: input, day: 3, challengeID: story.id, overlayText: "My caption")
        let reloaded = makeStore()
        let saved = try XCTUnwrap(reloaded.challenge(story.id))
        XCTAssertEqual(saved.mode, .sevenDay)
        XCTAssertEqual(saved.cards.map(\.day), Array(1...7))
        XCTAssertEqual(saved.momentTitles, prompts)
        XCTAssertEqual(saved.cards[2].overlayText, "My caption")
        let copied = try XCTUnwrap(reloaded.clipURL(for: saved.cards[2], in: story.id))
        XCTAssertNotEqual(copied, input)
        XCTAssertEqual(try Data(contentsOf: copied), try Data(contentsOf: input))
        XCTAssertTrue(copied.path.hasPrefix(files.root.path + "/"))
        reloaded.delete(story.id)
        XCTAssertTrue(files.loadChallenges().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }
}
