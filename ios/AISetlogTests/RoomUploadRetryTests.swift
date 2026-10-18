import XCTest
@testable import AISetlog

/// A take whose upload failed has to reach the room on a later sync.
///
/// `saveClip` uploads once, at record time. Before `syncRoom` retried, a take
/// that missed that one chance — no network, iCloud refusing the app — stayed
/// on the phone that filmed it: pending to its owner, absent for everyone else.
@MainActor
final class RoomUploadRetryTests: XCTestCase {
    private let code = "KPADC7"
    private let filmedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private var dir: URL!
    private var server: FakeRoomServer!
    private var store: ChallengeStore!
    private var me: AccountStore.Account!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomUploadRetryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        server = FakeRoomServer()
        let files = TempClipFileStore(root: dir)
        store = ChallengeStore(
            repository: InMemoryChallengeRepository(), fileStore: files,
            roomSync: RoomSyncService(fileStore: files, transport: server.transport),
            effects: Self.cloudEffects)
        let account = AccountStore()
        account.signInAsTester(named: "Me")
        store.account = account
        me = account.account
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "account.v1")
        try? FileManager.default.removeItem(at: dir)
        store = nil
        server = nil
        me = nil
        try super.tearDownWithError()
    }

    /// Cloud allowed, everything else a no-op: the retry is gated on
    /// `allowsCloudRoomManagement`, and reminders must not fire from a test.
    private static var cloudEffects: ChallengeStoreEffects {
        ChallengeStoreEffects(
            allowsCloudRoomManagement: true,
            reconcileReminders: { _ in },
            reconcileSubscriptions: { _ in },
            resetNotificationPreferences: {})
    }

    // MARK: - Fixtures

    /// A room where I filmed moment 1 at `filmedAt`, with the file on disk.
    private func roomWithMyTake() throws -> Challenge {
        let room = Challenge(
            id: UUID(),
            title: "A perfect day",
            startDate: filmedAt,
            cards: [
                DayCard(day: 1, clipFileName: "day1.mov", recordedAt: filmedAt, overlayText: "hi"),
                DayCard(day: 2),
            ],
            mode: .oneDay,
            clipLength: .tiny,
            orientation: .portrait,
            momentTitles: ["Morning", "Night"],
            roomCode: code,
            ownerName: "Leo",
            ownerID: "owner-1")
        let file = dir.appendingPathComponent(room.id.uuidString)
            .appendingPathComponent("day1.mov")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("take".utf8).write(to: file)
        store.challenges = [room]
        return room
    }

    private func myRoomCopy(day: Int, at date: Date) -> CloudKitService.RemoteClip {
        CloudKitService.RemoteClip(
            id: CloudKitService.clipRecordName(code: code, authorID: me.id, day: day),
            day: day, authorID: me.id, authorName: "Me", recordedAt: date,
            localURL: dir.appendingPathComponent("remote-day\(day).mov"), overlayText: nil)
    }

    // MARK: - Tests

    func testATakeTheRoomNeverGotIsUploadedOnTheNextSync() async throws {
        let room = try roomWithMyTake()

        await store.syncRoom(room.id)

        XCTAssertEqual(server.uploads.map(\.day), [1])
        XCTAssertEqual(server.uploads.first?.authorID, me.id)
        XCTAssertEqual(server.uploads.first?.overlayText, "hi")
        // Pulled again after the upload, so the room's copy replaces "pending".
        XCTAssertEqual(server.fetches, 2)
        XCTAssertEqual(store.roomSync.remoteClips[code]?.map(\.day), [1])
    }

    func testATakeAlreadyInTheRoomIsNotSentAgain() async throws {
        let room = try roomWithMyTake()
        server.clips = [myRoomCopy(day: 1, at: filmedAt.addingTimeInterval(5))]

        await store.syncRoom(room.id)

        XCTAssertTrue(server.uploads.isEmpty)
        XCTAssertEqual(server.fetches, 1)
    }

    /// Re-filmed, and the new take's upload failed: the room still holds the
    /// older one, which is the case "is it in the room at all" would miss.
    func testAReRecordTheRoomHasAnOlderCopyOfIsUploaded() async throws {
        let room = try roomWithMyTake()
        server.clips = [myRoomCopy(day: 1, at: filmedAt.addingTimeInterval(-60))]

        await store.syncRoom(room.id)

        XCTAssertEqual(server.uploads.map(\.day), [1])
    }

    /// A retried upload says when the take was filmed, not when the retry ran.
    ///
    /// The bug this pins: a clip filmed at 2:06 whose first upload failed went
    /// up on a later sync stamped with that sync's time, and friends saw 3:21.
    func testARetriedUploadCarriesWhenTheTakeWasFilmed() async throws {
        let room = try roomWithMyTake()

        await store.syncRoom(room.id)

        XCTAssertEqual(server.uploads.first?.recordedAt, filmedAt)
        XCTAssertEqual(store.roomSync.remoteClips[code]?.first?.recordedAt, filmedAt)
    }

    /// And once it is up with the take's own time, the next sync sees the same
    /// take rather than an older one and leaves it alone.
    func testATakeRetriedOnceIsNotRetriedAgain() async throws {
        let room = try roomWithMyTake()

        await store.syncRoom(room.id)
        await store.syncRoom(room.id)

        XCTAssertEqual(server.uploads.count, 1)
    }

    /// A take saved with an explicit time — a filed draft — keeps it on the
    /// card and on the way up.
    func testSavingAClipWithItsOwnTimeStampsTheCardAndTheUpload() async throws {
        let room = try roomWithMyTake()
        let draftTime = filmedAt.addingTimeInterval(-3_600)
        let source = dir.appendingPathComponent("draft.mov")
        try Data("draft".utf8).write(to: source)

        store.saveClip(from: source, day: 2, challengeID: room.id, recordedAt: draftTime)

        XCTAssertEqual(
            store.challenge(room.id)?.cards.first { $0.day == 2 }?.recordedAt, draftTime)
        // The upload runs in a Task; give it the turn it needs.
        for _ in 0..<50 where !server.uploads.contains(where: { $0.day == 2 }) {
            await Task.yield()
        }
        XCTAssertEqual(server.uploads.first { $0.day == 2 }?.recordedAt, draftTime)
    }

    /// A failed fetch says nothing about what the room has, so nothing goes up.
    func testNothingIsUploadedWhenTheRoomCannotBeRead() async throws {
        let room = try roomWithMyTake()
        server.fetchFails = true

        await store.syncRoom(room.id)

        XCTAssertTrue(server.uploads.isEmpty)
    }

    func testAnIsolatedStoreNeverUploads() async throws {
        let files = TempClipFileStore(root: dir)
        store = ChallengeStore(
            repository: InMemoryChallengeRepository(), fileStore: files,
            roomSync: RoomSyncService(fileStore: files, transport: server.transport),
            effects: .isolated)
        let account = AccountStore()
        account.signInAsTester(named: "Me")
        store.account = account
        me = account.account
        let room = try roomWithMyTake()

        await store.syncRoom(room.id)

        XCTAssertTrue(server.uploads.isEmpty)
    }
}

// MARK: - Doubles

/// A room that remembers what was uploaded to it and serves it back.
@MainActor
private final class FakeRoomServer {
    struct Upload { let day: Int; let authorID: String; let overlayText: String?; let recordedAt: Date }

    var clips: [CloudKitService.RemoteClip] = []
    var fetchFails = false
    private(set) var uploads: [Upload] = []
    private(set) var fetches = 0

    var transport: RoomSyncTransport {
        RoomSyncTransport(
            fetchClips: { [self] _, _ in
                fetches += 1
                if fetchFails { throw CancellationError() }
                return clips
            },
            fetchInteractions: { _ in ([], []) },
            uploadClip: { [self] code, day, authorID, authorName, file, caption, recordedAt in
                uploads.append(Upload(
                    day: day, authorID: authorID, overlayText: caption, recordedAt: recordedAt))
                clips.removeAll { $0.authorID == authorID && $0.day == day }
                // Stores what it was told, like the real record does now.
                clips.append(CloudKitService.RemoteClip(
                    id: CloudKitService.clipRecordName(code: code, authorID: authorID, day: day),
                    day: day, authorID: authorID, authorName: authorName, recordedAt: recordedAt,
                    localURL: file, overlayText: caption))
            },
            updateClipCaption: { _, _, _, _ in },
            setReaction: { _, _, _, _, _, _, _ in },
            postComment: { _, _, _, _, _, _, _ in },
            deleteComment: { _ in })
    }
}

private final class TempClipFileStore: ClipFileStore {
    let root: URL
    init(root: URL) { self.root = root }

    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? { "day\(day).mov" }
    func clipURL(fileName: String, challengeID: UUID) -> URL {
        root.appendingPathComponent(challengeID.uuidString).appendingPathComponent(fileName)
    }
    func deleteClips(challengeID: UUID) {}
    func remoteCacheDir(roomCode: String) -> URL {
        root.appendingPathComponent("room-\(roomCode)", isDirectory: true)
    }
    func deleteRemoteCache(roomCode: String) {}
    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {}
}

private final class InMemoryChallengeRepository: ChallengeRepository {
    private var challenges: [Challenge] = []
    private var templates: [ChallengeTemplate] = []
    func loadChallenges() -> [Challenge] { challenges }
    func saveChallenges(_ challenges: [Challenge]) { self.challenges = challenges }
    func loadTemplates() -> [ChallengeTemplate] { templates }
    func saveTemplates(_ templates: [ChallengeTemplate]) { self.templates = templates }
}
