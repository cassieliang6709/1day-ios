import XCTest
@testable import AISetlog

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

    private static var cloudEffects: ChallengeStoreEffects {
        ChallengeStoreEffects(
            allowsCloudRoomManagement: true,
            reconcileReminders: { _ in },
            reconcileSubscriptions: { _ in },
            resetNotificationPreferences: {})
    }


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


    func testMyTakesInTheRoomBecomeThisPhonesAgain() async throws {
        let room = Challenge(
            id: UUID(), title: "A perfect day", startDate: filmedAt,
            cards: [DayCard(day: 1), DayCard(day: 2)],
            mode: .oneDay, clipLength: .tiny, orientation: .portrait,
            momentTitles: ["Morning", "Night"],
            roomCode: code, ownerName: "Leo", ownerID: "owner-1")
        store.challenges = [room]
        let file = dir.appendingPathComponent("remote.mov")
        try Data("take".utf8).write(to: file)
        server.clips = [
            CloudKitService.RemoteClip(
                id: CloudKitService.clipRecordName(code: code, authorID: me.id, day: 1),
                day: 1, authorID: me.id, authorName: "Me", recordedAt: filmedAt,
                localURL: file, overlayText: "hi"),
            CloudKitService.RemoteClip(
                id: CloudKitService.clipRecordName(code: code, authorID: "leo", day: 2),
                day: 2, authorID: "leo", authorName: "Leo", recordedAt: filmedAt,
                localURL: file, overlayText: nil),
        ]

        await store.syncRoom(room.id)

        let cards = try XCTUnwrap(store.challenge(room.id)).cards
        XCTAssertEqual(cards[0].clipFileName, "day1.mov")
        XCTAssertEqual(cards[0].recordedAt, filmedAt)
        XCTAssertEqual(cards[0].captions.firstText, "hi")
        XCTAssertNil(cards[1].clipFileName, "Leo's take stays Leo's")
        XCTAssertEqual(ClipFiling.targetDay(in: try XCTUnwrap(store.challenge(room.id))), 2)
        XCTAssertTrue(server.uploads.isEmpty, "nothing of mine is sent back over itself")
    }

    func testATakeTheRoomNeverGotIsUploadedOnTheNextSync() async throws {
        let room = try roomWithMyTake()

        await store.syncRoom(room.id)

        XCTAssertEqual(server.uploads.map(\.day), [1])
        XCTAssertEqual(server.uploads.first?.authorID, me.id)
        XCTAssertEqual(server.uploads.first?.overlayText, "hi")
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

    func testAReRecordTheRoomHasAnOlderCopyOfIsUploaded() async throws {
        let room = try roomWithMyTake()
        server.clips = [myRoomCopy(day: 1, at: filmedAt.addingTimeInterval(-60))]

        await store.syncRoom(room.id)

        XCTAssertEqual(server.uploads.map(\.day), [1])
    }

    func testARetriedUploadCarriesWhenTheTakeWasFilmed() async throws {
        let room = try roomWithMyTake()

        await store.syncRoom(room.id)

        XCTAssertEqual(server.uploads.first?.recordedAt, filmedAt)
        XCTAssertEqual(store.roomSync.remoteClips[code]?.first?.recordedAt, filmedAt)
    }

    func testATakeRetriedOnceIsNotRetriedAgain() async throws {
        let room = try roomWithMyTake()

        await store.syncRoom(room.id)
        await store.syncRoom(room.id)

        XCTAssertEqual(server.uploads.count, 1)
    }

    func testSavingAClipWithItsOwnTimeStampsTheCardAndTheUpload() async throws {
        let room = try roomWithMyTake()
        let draftTime = filmedAt.addingTimeInterval(-3_600)
        let source = dir.appendingPathComponent("draft.mov")
        try Data("draft".utf8).write(to: source)

        store.saveClip(from: source, day: 2, challengeID: room.id, recordedAt: draftTime)

        XCTAssertEqual(
            store.challenge(room.id)?.cards.first { $0.day == 2 }?.recordedAt, draftTime)
        for _ in 0..<50 where !server.uploads.contains(where: { $0.day == 2 }) {
            await Task.yield()
        }
        XCTAssertEqual(server.uploads.first { $0.day == 2 }?.recordedAt, draftTime)
    }

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


    private func waitForUploads(_ count: Int) async {
        for _ in 0..<200 where server.uploads.count < count { await Task.yield() }
    }

    private func newTakeFile(_ name: String = "again.mov") throws -> URL {
        let source = dir.appendingPathComponent(name)
        try Data("again".utf8).write(to: source)
        return source
    }

    func testACardSavedBeforeTakesExistedStillDecodes() throws {
        let json = #"{"day":1,"clipFileName":"day1.mov","overlayText":"hi","reactions":[],"comments":[]}"#
        let card = try JSONDecoder().decode(DayCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.clipFileName, "day1.mov")
        XCTAssertEqual(card.overlayText, "hi")
        XCTAssertTrue(card.moreTakes.isEmpty)
        var withTake = card
        withTake.moreTakes = [ClipTake(
            id: UUID(), fileName: "day1_x.mov", recordedAt: filmedAt,
            overlayText: "two", captionSticker: nil)]
        let back = try JSONDecoder().decode(DayCard.self, from: JSONEncoder().encode(withTake))
        XCTAssertEqual(back.moreTakes, withTake.moreTakes)
    }

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
        let takeOne = dir.appendingPathComponent(room.id.uuidString).appendingPathComponent("day1.mov")
        XCTAssertEqual(try Data(contentsOf: takeOne), Data("take".utf8))

        store.saveClip(from: try newTakeFile("third.mov"), day: 1, challengeID: room.id, take: .append)
        XCTAssertEqual(store.challenge(room.id)?.cards.first { $0.day == 1 }?.moreTakes.count, 2)
    }

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
        let ids = Set(server.clips.map(\.id))
        XCTAssertTrue(ids.contains(CloudKitService.clipRecordName(code: code, authorID: me.id, day: 1)))
        XCTAssertTrue(ids.contains(name))
    }

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
        let files = try FileManager.default.contentsOfDirectory(
            atPath: dir.appendingPathComponent(room.id.uuidString).path)
        XCTAssertEqual(files, ["day1.mov"])
        XCTAssertEqual(server.uploads.map(\.takeID), [nil])
    }

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
        XCTAssertEqual(card.overlayText, "hi")
        XCTAssertEqual(card.recordedAt, filmedAt)
        let takeOne = dir.appendingPathComponent(room.id.uuidString).appendingPathComponent("day1.mov")
        XCTAssertEqual(try Data(contentsOf: takeOne), Data("take".utf8))
        XCTAssertEqual(server.uploads.map(\.takeID), [takeID])
    }

    func testRetakingAMissingTakeKeepsTheFootageAsANewTake() throws {
        let room = try roomWithMyTake()

        store.saveClip(from: try newTakeFile(), day: 1, challengeID: room.id, take: .replace(UUID()))

        let card = try XCTUnwrap(store.challenge(room.id)?.cards.first { $0.day == 1 })
        XCTAssertEqual(card.moreTakes.count, 1)
        XCTAssertEqual(card.overlayText, "hi")
        let takeOne = dir.appendingPathComponent(room.id.uuidString).appendingPathComponent("day1.mov")
        XCTAssertEqual(try Data(contentsOf: takeOne), Data("take".utf8))
    }

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

        store.roomSync.remoteClips[code]?.append(CloudKitService.RemoteClip(
            id: CloudKitService.clipRecordName(code: code, authorID: me.id, day: 1, takeID: takeID),
            day: 1, authorID: me.id, authorName: "Me", recordedAt: filmedAt.addingTimeInterval(60),
            localURL: dir.appendingPathComponent("remote-take2.mov"), overlayText: "two"))
        let synced = store.recordedClips(for: room.id)
        XCTAssertEqual(synced.count, 2)
        XCTAssertEqual(synced.last?.takeID, takeID)
        XCTAssertEqual(synced.last?.url, dir.appendingPathComponent("remote-take2.mov"))
    }

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

        await store.syncRoom(room.id)
        XCTAssertEqual(server.uploads.count, 1)
    }

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


    private var twoCaptions: [Caption] {
        [Caption(text: "hi", sticker: CaptionSticker(x: 0.5, y: 0.2, style: .band)),
         Caption(text: "second", sticker: CaptionSticker(x: 0.3, y: 0.8, style: .solid))]
    }

    func testTheRetriedUploadCarriesEveryCaption() async throws {
        var room = try roomWithMyTake()
        room.cards[0].captions = twoCaptions
        store.challenges = [room]

        await store.syncRoom(room.id)

        XCTAssertEqual(server.uploads.first?.captions.map(\.text), ["hi", "second"])
        XCTAssertEqual(server.uploads.first?.overlayText, "hi")
    }

    func testUpdatingCaptionsPushesTheWholeList() async throws {
        let room = try roomWithMyTake()

        store.updateCaptions(twoCaptions, day: 1, challengeID: room.id)
        for _ in 0..<20 where server.captionUpdates.isEmpty { await Task.yield() }

        XCTAssertEqual(store.challenge(room.id)?.cards.first?.captions.count, 2)
        XCTAssertEqual(store.challenge(room.id)?.cards.first?.overlayText, "hi")
        XCTAssertEqual(server.captionUpdates.last?.map(\.text), ["hi", "second"])
    }

    func testMyRoomClipShowsLocalCaptionsOverTheRoomsSingleOne() throws {
        var room = try roomWithMyTake()
        room.cards[0].captions = twoCaptions
        store.challenges = [room]
        var copy = myRoomCopy(day: 1, at: filmedAt)
        copy = CloudKitService.RemoteClip(
            id: copy.id, day: 1, authorID: me.id, authorName: "Me", recordedAt: filmedAt,
            localURL: copy.localURL, overlayText: "hi")
        store.roomSync.remoteClips[code] = [copy]

        let clips = store.recordedClips(for: room.id)

        XCTAssertEqual(clips.first?.captions.map(\.text), ["hi", "second"])
    }
}


@MainActor
private final class FakeRoomServer {
    struct Upload {
        let day: Int; let authorID: String; let captions: [Caption]; let recordedAt: Date
        var takeID: UUID? = nil
        var overlayText: String? { captions.firstText }
    }

    var clips: [CloudKitService.RemoteClip] = []
    var fetchFails = false
    private(set) var uploads: [Upload] = []
    private(set) var captionUpdates: [[Caption]] = []
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
                    day: day, authorID: authorID, captions: caption, recordedAt: recordedAt,
                    takeID: takeID))
                let name = CloudKitService.clipRecordName(
                    code: code, authorID: authorID, day: day, takeID: takeID)
                clips.removeAll { $0.id == name }
                clips.append(CloudKitService.RemoteClip(
                    id: name,
                    day: day, authorID: authorID, authorName: authorName, recordedAt: recordedAt,
                    localURL: file, overlayText: caption.firstText,
                    captionSticker: caption.first?.sticker,
                    captionsJSON: Caption.cloudJSON(caption)))
            },
            updateClipCaption: { [self] _, _, _, captions, _ in captionUpdates.append(captions) },
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
    func loadChallenges() -> [Challenge] { challenges }
    func saveChallenges(_ challenges: [Challenge]) { self.challenges = challenges }
}
