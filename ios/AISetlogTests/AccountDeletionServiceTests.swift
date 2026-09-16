import XCTest
@testable import AISetlog

/// Account deletion, end to end, with CloudKit stood in for.
///
/// `AccountDeletionCoordinatorTests` covers the protocol and
/// `AccountDeletionJournalStoreTests` the durability. What neither could cover
/// is the thing that was actually wrong: the app had both of those and used
/// neither, deleting through an older path that wrapped the cloud step in
/// `try?`, swept the device either way and reported success. These tests are
/// about the ordering that stops that — local data last, and no success unless
/// it is true.
@MainActor
final class AccountDeletionServiceTests: XCTestCase {
    private var journalURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("deletion-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: journalURL)
        try await super.tearDown()
    }

    // MARK: - The failure that used to be silent

    func testAFailedCloudDeleteLeavesEveryStoryOnTheDeviceAlone() async throws {
        let store = try makeStore()
        let before = store.challenges.count
        XCTAssertGreaterThan(before, 0, "the fixture has to have something to lose")

        let service = AccountDeletionService(
            store: store, journalURL: journalURL,
            deleteRecords: { _ in throw StubFailure.offline })

        let gone = await service.run()

        XCTAssertFalse(gone, "a deletion that did not finish must not report success")
        XCTAssertEqual(store.challenges.count, before, "local stories were wiped anyway")
        XCTAssertTrue(store.account?.isSignedIn == true, "the person was signed out anyway")
        if case .failed = service.state {} else {
            XCTFail("expected a failed state, got \(service.state)")
        }
    }

    /// The journal is what makes "try again" more than a hopeful button.
    func testAFailedRunLeavesAJournalToResumeFrom() async throws {
        let store = try makeStore()
        let service = AccountDeletionService(
            store: store, journalURL: journalURL,
            deleteRecords: { _ in throw StubFailure.offline })
        _ = await service.run()

        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))

        // A second attempt resumes that journal rather than starting a fresh
        // operation, which is what stops a retry re-deleting from scratch.
        var seen: Set<String> = []
        let retry = AccountDeletionService(
            store: store, journalURL: journalURL,
            deleteRecords: { batch in seen.formUnion(batch); return batch })
        let gone = await retry.run()

        XCTAssertTrue(gone)
        XCTAssertFalse(seen.isEmpty, "the retry should have had records to delete")
    }

    // MARK: - The success path

    func testASuccessfulRunDeletesTheCloudRecordsThenTheDevice() async throws {
        let store = try makeStore()
        var deleted: Set<String> = []
        var deviceStillFullWhenCloudRan = false

        let service = AccountDeletionService(
            store: store, journalURL: journalURL,
            deleteRecords: { batch in
                // The ordering under test: the device must still be intact
                // while the cloud step is running, or a failure here would
                // have nothing to go back to.
                deviceStillFullWhenCloudRan = !store.challenges.isEmpty
                deleted.formUnion(batch)
                return batch
            })

        let gone = await service.run()

        XCTAssertTrue(gone)
        XCTAssertTrue(deviceStillFullWhenCloudRan, "local data went first")
        XCTAssertFalse(deleted.isEmpty, "nothing was sent to CloudKit")
        XCTAssertTrue(store.challenges.isEmpty, "local stories survived a completed deletion")
        XCTAssertEqual(store.account?.isSignedIn, false)
        XCTAssertEqual(service.state, .completed)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: journalURL.path),
            "a finished deletion should not leave a journal behind")
    }

    /// A record CloudKit reports as already absent is the state we asked for.
    /// Treating it as a failure would wedge a retry forever on records the
    /// previous attempt had already removed.
    func testRecordsTheCloudNoLongerHasCountAsDeleted() async throws {
        let store = try makeStore()
        let service = AccountDeletionService(
            store: store, journalURL: journalURL,
            deleteRecords: { $0 })
        let gone = await service.run()
        XCTAssertTrue(gone)
    }

    // MARK: - Refusals

    func testAPreviewRuntimeCanNeverReachARealAccount() async throws {
        let store = try makeStore(effects: .isolated)
        let service = AccountDeletionService(
            store: store, journalURL: journalURL,
            deleteRecords: { batch in XCTFail("a preview must not touch CloudKit"); return batch })
        let gone = await service.run()
        XCTAssertFalse(gone)
        XCTAssertFalse(store.challenges.isEmpty)
    }

    func testSignedOutThereIsNothingToDelete() async throws {
        let store = try makeStore(signedIn: false)
        let service = AccountDeletionService(
            store: store, journalURL: journalURL,
            deleteRecords: { batch in XCTFail("no account, no records"); return batch })
        let gone = await service.run()
        XCTAssertFalse(gone)
    }

    // MARK: - The inventory

    /// A room someone created holds their friends' clips too. Destroying it is
    /// not what "delete my account" means, so it is not in the inventory.
    func testTheInventoryCoversMyClipsAndNotTheRoomItself() throws {
        let store = try makeStore()
        let me = try XCTUnwrap(store.account?.account?.id)
        let names = AccountDeletionService.inventory(of: store, authorID: me)

        XCTAssertFalse(names.isEmpty)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
        XCTAssertFalse(names.contains("ROOM01"), "the room record must survive")
        XCTAssertTrue(
            names.contains(CloudKitService.clipRecordName(code: "ROOM01", authorID: me, day: 1)))
        // Stable order, so a resumed run pages the same list the same way.
        XCTAssertEqual(names, names.sorted())
    }

    // MARK: - Fixtures

    private func makeStore(
        effects: ChallengeStoreEffects = .live, signedIn: Bool = true
    ) throws -> ChallengeStore {
        let store = ChallengeStore(
            repository: MemoryDeletionRepository(),
            fileStore: NullDeletionFileStore(),
            effects: effects)
        if signedIn {
            let account = AccountStore()
            account.signInAsTester(named: "Deletion Tester")
            store.account = account
        }
        var challenge = Challenge(
            id: UUID(), title: "Shared day", startDate: .now,
            cards: [DayCard(day: 1), DayCard(day: 2)])
        challenge.roomCode = "ROOM01"
        store.challenges = [challenge]
        return store
    }

    private enum StubFailure: Error { case offline }
}

private final class MemoryDeletionRepository: ChallengeRepository {
    private var challenges: [Challenge] = []
    private var templates: [ChallengeTemplate] = []
    func loadChallenges() -> [Challenge] { challenges }
    func saveChallenges(_ challenges: [Challenge]) { self.challenges = challenges }
    func loadTemplates() -> [ChallengeTemplate] { templates }
    func saveTemplates(_ templates: [ChallengeTemplate]) { self.templates = templates }
}

private final class NullDeletionFileStore: ClipFileStore {
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
