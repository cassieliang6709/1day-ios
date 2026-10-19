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

    // MARK: - Multiple takes of one moment

    /// Waits out the upload `saveClip` starts in a Task.
    private func waitForUploads(_ count: Int) async {
        for _ in 0..<200 where server.uploads.count < count { await Task.yield() }
    }

    private func newTakeFile(_ name: String = "again.mov") throws -> URL {
        let source = dir.appendingPathComponent(name)
        try Data("again".utf8).write(to: source)
        return source
    }

    /// A card written before takes existed has no `moreTakes` key at all.
    func testACardSavedBeforeTakesExistedStillDecodes() throws {
        let json = #"{"day":1,"clipFileName":"day1.mov","overlayText":"hi","reactions":[],"comments":[]}"#
        let card = try JSONDecoder().decode(DayCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.clipFileName, "day1.mov")
        XCTAssertEqual(card.overlayText, "hi")
        XCTAssertTrue(card.moreTakes.isEmpty)
        // And a card with takes round-trips them.
        var withTake = card
        withTake.moreTakes = [ClipTake(
            id: UUID(), fileName: "day1_x.mov", recordedAt: filmedAt,
            overlayText: "two", captionSticker: nil)]
        let back = try JSONDecoder().decode(DayCard.self, from: JSONEncoder().encode(withTake))
        XCTAssertEqual(back.moreTakes, withTake.moreTakes)
    }

    /// 再拍一段 adds a take; take 1 is exactly where it was.
    func testASecondTakeIsAppendedAndTheFirstIsKept() async throws {
        let room = try roomWithMyTake()
        let second = filmedAt.addingTimeInterval(600)

        store.saveClip(
            from: try newTakeFile(), day: 1, challengeID: room.id,
            overlayText: "again", recordedAt: second, take: .append)

        let card = try XCTUnwrap(store.challenge(room.id)?.cards.first { $0.day == 1 })
        XCTAssertEqual(card.clipFileName, "day1.mov")
        XCTAssertEqual(card.recordedAt, filmedAt)
        XCTAssertEqual(card.overlayText, "hi")
        XCTAssertEqual(card.moreTakes.count, 1)
        let take = try XCTUnwrap(card.moreTakes.first)
        XCTAssertEqual(take.fileName, "day1_\(take.id.uuidString).mov")
        XCTAssertEqual(take.recordedAt, second)
        XCTAssertEqual(take.overlayText, "again")
        // Take 1's file was not touched.
        let takeOne = dir.appendingPathComponent(room.id.uuidString).appendingPathComponent("day1.mov")
        XCTAssertEqual(try Data(contentsOf: takeOne), Data("take".utf8))

        // A third take appends again rather than replacing the second.
        store.saveClip(from: try newTakeFile("third.mov"), day: 1, challengeID: room.id, take: .append)
        XCTAssertEqual(store.challenge(room.id)?.cards.first { $0.day == 1 }?.moreTakes.count, 2)
    }

    /// The extra take goes up under its own record, never take 1's.
    func testAnExtraTakeUploadsUnderItsOwnRecordName() async throws {
        let room = try roomWithMyTake()
        server.clips = [myRoomCopy(day: 1, at: filmedAt)]

        store.saveClip(from: try newTakeFile(), day: 1, challengeID: room.id, take: .append)
        await waitForUploads(1)

        let take = try XCTUnwrap(store.challenge(room.id)?.cards.first { $0.day == 1 }?.moreTakes.first)
        XCTAssertEqual(server.uploads.map(\.takeID), [take.id])
        let name = CloudKitService.clipRecordName(code: code, authorID: me.id, day: 1, takeID: take.id)
        XCTAssertEqual(name, "\(code)_\(me.id)_day1_\(take.id.uuidString)")
        XCTAssertEqual(
            CloudKitService.takeID(fromClipRecordName: name, code: code, authorID: me.id, day: 1),
            take.id)
        XCTAssertNil(CloudKitService.takeID(
            fromClipRecordName: CloudKitService.clipRecordName(code: code, authorID: me.id, day: 1),
            code: code, authorID: me.id, day: 1))
        // Both takes are in the room now, take 1 untouched.
        let ids = Set(server.clips.map(\.id))
        XCTAssertTrue(ids.contains(CloudKitService.clipRecordName(code: code, authorID: me.id, day: 1)))
        XCTAssertTrue(ids.contains(name))
    }

    /// 重拍 on take 1 replaces it in place — file, card and room record —
    /// rather than adding a take. This is the default every caller gets.
    func testRetakingTakeOneReplacesIt() async throws {
        let room = try roomWithMyTake()
        let later = filmedAt.addingTimeInterval(600)

        store.saveClip(
            from: try newTakeFile(), day: 1, challengeID: room.id,
            overlayText: "new", recordedAt: later)
        await waitForUploads(1)

        let card = try XCTUnwrap(store.challenge(room.id)?.cards.first { $0.day == 1 })
        XCTAssertEqual(card.clipFileName, "day1.mov")
        XCTAssertEqual(card.recordedAt, later)
        XCTAssertEqual(card.overlayText, "new")
        XCTAssertTrue(card.moreTakes.isEmpty)
        // No second file next to take 1. (Overwriting `day1.mov` itself is
        // `DiskClipFileStore.storeClip`; this test's store doesn't write it.)
        let files = try FileManager.default.contentsOfDirectory(
            atPath: dir.appendingPathComponent(room.id.uuidString).path)
        XCTAssertEqual(files, ["day1.mov"])
        XCTAssertEqual(server.uploads.map(\.takeID), [nil])
    }

    /// 重拍 on take 2 replaces take 2 under the same id — so the same file name
    /// and the same room record — and leaves take 1 alone.
    func testRetakingAnExtraTakeReplacesOnlyThatTake() async throws {
        var room = try roomWithMyTake()
        let takeID = UUID()
        let fileName = "day1_\(takeID.uuidString).mov"
        let takeFile = dir.appendingPathComponent(room.id.uuidString).appendingPathComponent(fileName)
        try Data("two".utf8).write(to: takeFile)
        room.cards[0].moreTakes = [ClipTake(
            id: takeID, fileName: fileName, recordedAt: filmedAt.addingTimeInterval(60),
            overlayText: "two", captionSticker: nil)]
        store.challenges = [room]
        // The room already has take 1, so the sync after the upload has
        // nothing of take 1 to retry.
        server.clips = [myRoomCopy(day: 1, at: filmedAt)]
        let later = filmedAt.addingTimeInterval(600)

        store.saveClip(
            from: try newTakeFile(), day: 1, challengeID: room.id,
            overlayText: "two again", recordedAt: later, take: .replace(takeID))
        await waitForUploads(1)

        let card = try XCTUnwrap(store.challenge(room.id)?.cards.first { $0.day == 1 })
        XCTAssertEqual(card.moreTakes.map(\.id), [takeID])
        XCTAssertEqual(card.moreTakes.first?.fileName, fileName)
        XCTAssertEqual(card.moreTakes.first?.recordedAt, later)
        XCTAssertEqual(card.moreTakes.first?.overlayText, "two again")
        XCTAssertEqual(try Data(contentsOf: takeFile), Data("again".utf8))
        // Take 1 untouched.
        XCTAssertEqual(card.overlayText, "hi")
        XCTAssertEqual(card.recordedAt, filmedAt)
        let takeOne = dir.appendingPathComponent(room.id.uuidString).appendingPathComponent("day1.mov")
        XCTAssertEqual(try Data(contentsOf: takeOne), Data("take".utf8))
        XCTAssertEqual(server.uploads.map(\.takeID), [takeID])
    }

    /// 重拍 on a take that's gone by the time the camera hands back keeps the
    /// footage as a new take rather than dropping it or touching take 1.
    func testRetakingAMissingTakeKeepsTheFootageAsANewTake() throws {
        let room = try roomWithMyTake()

        store.saveClip(from: try newTakeFile(), day: 1, challengeID: room.id, take: .replace(UUID()))

        let card = try XCTUnwrap(store.challenge(room.id)?.cards.first { $0.day == 1 })
        XCTAssertEqual(card.moreTakes.count, 1)
        XCTAssertEqual(card.overlayText, "hi")
        let takeOne = dir.appendingPathComponent(room.id.uuidString).appendingPathComponent("day1.mov")
        XCTAssertEqual(try Data(contentsOf: takeOne), Data("take".utf8))
    }

    /// The room has take 1; take 2 is still only here. Both show, once each.
    func testAPendingExtraTakeShowsBesideTheRoomsTakeOne() throws {
        var room = try roomWithMyTake()
        let takeID = UUID()
        room.cards[0].moreTakes = [ClipTake(
            id: takeID, fileName: "day1_\(takeID.uuidString).mov",
            recordedAt: filmedAt.addingTimeInterval(60), overlayText: "two", captionSticker: nil)]
        store.challenges = [room]
        store.roomSync.remoteClips[code] = [myRoomCopy(day: 1, at: filmedAt)]

        let clips = store.recordedClips(for: room.id)

        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips.map(\.takeID), [nil, takeID])
        XCTAssertEqual(Set(clips.map(\.id)).count, 2)
        XCTAssertEqual(clips.last?.overlayText, "two")

        // Once the room has take 2 as well, it is the room's copy that shows.
        store.roomSync.remoteClips[code]?.append(CloudKitService.RemoteClip(
            id: CloudKitService.clipRecordName(code: code, authorID: me.id, day: 1, takeID: takeID),
            day: 1, authorID: me.id, authorName: "Me", recordedAt: filmedAt.addingTimeInterval(60),
            localURL: dir.appendingPathComponent("remote-take2.mov"), overlayText: "two"))
        let synced = store.recordedClips(for: room.id)
        XCTAssertEqual(synced.count, 2)
        XCTAssertEqual(synced.last?.takeID, takeID)
        XCTAssertEqual(synced.last?.url, dir.appendingPathComponent("remote-take2.mov"))
    }

    /// An extra take whose upload failed is retried, and take 1 is left alone.
    func testARetryUploadsAMissingExtraTake() async throws {
        var room = try roomWithMyTake()
        let takeID = UUID()
        let fileName = "day1_\(takeID.uuidString).mov"
        try Data("two".utf8).write(to: dir.appendingPathComponent(room.id.uuidString)
            .appendingPathComponent(fileName))
        let second = filmedAt.addingTimeInterval(60)
        room.cards[0].moreTakes = [ClipTake(
            id: takeID, fileName: fileName, recordedAt: second,
            overlayText: "two", captionSticker: nil)]
        store.challenges = [room]
        server.clips = [myRoomCopy(day: 1, at: filmedAt)]

        await store.syncRoom(room.id)

        XCTAssertEqual(server.uploads.count, 1)
        XCTAssertEqual(server.uploads.first?.takeID, takeID)
        XCTAssertEqual(server.uploads.first?.recordedAt, second)
        XCTAssertEqual(server.uploads.first?.overlayText, "two")

        // And not again once it is there.
        await store.syncRoom(room.id)
        XCTAssertEqual(server.uploads.count, 1)
    }

    /// Editing an extra take's caption changes that take, not take 1.
    func testACaptionEditOnAnExtraTakeStaysOnThatTake() throws {
        var room = try roomWithMyTake()
        let takeID = UUID()
        room.cards[0].moreTakes = [ClipTake(
            id: takeID, fileName: "day1_x.mov", recordedAt: filmedAt,
            overlayText: "two", captionSticker: nil)]
        store.challenges = [room]

        store.updateOverlayText("edited", day: 1, challengeID: room.id, takeID: takeID)
        store.updateCaptionSticker(.default, day: 1, challengeID: room.id, takeID: takeID)

        let card = try XCTUnwrap(store.challenge(room.id)?.cards.first)
        XCTAssertEqual(card.overlayText, "hi")
        XCTAssertNil(card.captionSticker)
        XCTAssertEqual(card.moreTakes.first?.overlayText, "edited")
        XCTAssertEqual(card.moreTakes.first?.captionSticker, .default)
    }

    /// Deleting the account names every extra take, the ones on this phone and
    /// the ones only the room has.
    func testAccountDeletionInventoryIncludesExtraTakes() throws {
        var room = try roomWithMyTake()
        let local = UUID()
        let elsewhere = UUID()
        room.cards[0].moreTakes = [ClipTake(
            id: local, fileName: "day1_x.mov", recordedAt: filmedAt,
            overlayText: nil, captionSticker: nil)]
        store.challenges = [room]
        let remoteOnly = CloudKitService.clipRecordName(
            code: code, authorID: me.id, day: 2, takeID: elsewhere)
        store.roomSync.remoteClips[code] = [CloudKitService.RemoteClip(
            id: remoteOnly, day: 2, authorID: me.id, authorName: "Me", recordedAt: filmedAt,
            localURL: dir.appendingPathComponent("r.mov"), overlayText: nil)]

        let inventory = AccountDeletionService.inventory(of: store, authorID: me.id)

        XCTAssertTrue(inventory.contains(
            CloudKitService.clipRecordName(code: code, authorID: me.id, day: 1)))
        XCTAssertTrue(inventory.contains(
            CloudKitService.clipRecordName(code: code, authorID: me.id, day: 1, takeID: local)))
        XCTAssertTrue(inventory.contains(remoteOnly))
        XCTAssertEqual(
            store.extraTakeRecordNames(in: room, authorID: me.id).sorted(),
            [CloudKitService.clipRecordName(code: code, authorID: me.id, day: 1, takeID: local),
             remoteOnly].sorted())
    }
}

// MARK: - Doubles

/// A room that remembers what was uploaded to it and serves it back.
@MainActor
private final class FakeRoomServer {
    struct Upload {
        let day: Int; let authorID: String; let overlayText: String?; let recordedAt: Date
        var takeID: UUID? = nil
    }

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
            uploadClip: { [self] code, day, authorID, authorName, file, caption, recordedAt, takeID in
                uploads.append(Upload(
                    day: day, authorID: authorID, overlayText: caption, recordedAt: recordedAt,
                    takeID: takeID))
                // One record per name, like CloudKit: a take overwrites only
                // itself.
                let name = CloudKitService.clipRecordName(
                    code: code, authorID: authorID, day: day, takeID: takeID)
                clips.removeAll { $0.id == name }
                // Stores what it was told, like the real record does now.
                clips.append(CloudKitService.RemoteClip(
                    id: name,
                    day: day, authorID: authorID, authorName: authorName, recordedAt: recordedAt,
                    localURL: file, overlayText: caption))
            },
            updateClipCaption: { _, _, _, _, _ in },
            setReaction: { _, _, _, _, _, _, _ in },
            postComment: { _, _, _, _, _, _, _ in },
            deleteComment: { _ in })
    }
}

private final class TempClipFileStore: ClipFileStore {
    let root: URL
    init(root: URL) { self.root = root }

    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? { "day\(day).mov" }
    func storeExtraTake(from tempURL: URL, day: Int, takeID: UUID, challengeID: UUID) -> String? {
        let name = "day\(day)_\(takeID.uuidString).mov"
        let dest = clipURL(fileName: name, challengeID: challengeID)
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        return (try? FileManager.default.copyItem(at: tempURL, to: dest)) == nil ? nil : name
    }
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
