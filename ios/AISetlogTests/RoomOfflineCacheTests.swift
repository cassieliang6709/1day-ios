import AVFoundation
import XCTest
@testable import AISetlog

@MainActor
final class RoomOfflineCacheTests: XCTestCase {
    private var files: OfflineRoomFiles!
    private var owner: String? = "account-a"
    private var offline = false
    private var clips: [CloudKitService.RemoteClip] = []
    private var reactions: [CloudKitService.RemoteReaction] = []
    private var comments: [CloudKitService.RemoteComment] = []
    private var fetchCount = 0
    private let room = Challenge(id: UUID(), title: "Friends", startDate: Date(), cards: [DayCard(day: 1)],
                                 roomCode: "ROOM", ownerName: "Friend", ownerID: "friend")

    override func setUpWithError() throws {
        files = OfflineRoomFiles()
        owner = "account-a"
        offline = false
        clips = []; reactions = []; comments = []; fetchCount = 0
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: files.root)
        files = nil
        super.tearDown()
    }

    private func transport() -> RoomSyncTransport {
        RoomSyncTransport(
            fetchClips: { [self] _, _ in
                fetchCount += 1
                if offline { throw URLError(.notConnectedToInternet) }
                return clips
            },
            fetchInteractions: { [self] _ in
                if offline { throw URLError(.notConnectedToInternet) }
                return (reactions, comments)
            },
            uploadClip: { _, _, _, _, _, _, _, _ in },
            updateClipCaption: { _, _, _, _, _ in },
            setReaction: { [self] _, _, _, _, _, _, _ in
                if offline { throw URLError(.notConnectedToInternet) }
            },
            postComment: { [self] _, _, _, _, _, _, _ in
                if offline { throw URLError(.notConnectedToInternet) }
            },
            deleteComment: { [self] _ in
                if offline { throw URLError(.notConnectedToInternet) }
            })
    }

    private func service(transport supplied: RoomSyncTransport? = nil) -> RoomSyncService {
        RoomSyncService(fileStore: files, transport: supplied ?? transport(), cacheAccountID: { [self] in owner })
    }

    private func store(_ sync: RoomSyncService) -> ChallengeStore {
        ChallengeStore(repository: OfflineRoomRepository(rooms: [room]), fileStore: files,
                       roomSync: sync, effects: .isolated)
    }

    private func clip(realVideo: Bool = false) async throws -> CloudKitService.RemoteClip {
        let directory = files.remoteCacheDir(roomCode: "ROOM")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ROOM_friend_day1.mov")
        if realVideo {
            let generated = await ClipFixtureFactory.makeClip(index: 0)
            let source = try XCTUnwrap(generated)
            defer { try? FileManager.default.removeItem(at: source) }
            try FileManager.default.copyItem(at: source, to: url)
        } else {
            try Data([1, 2, 3]).write(to: url)
        }
        let captions = [Caption(text: "今天的字幕 🌙", sticker: .default), Caption(text: "Second line")]
        return .init(id: "ROOM_friend_day1", day: 1, authorID: "friend", authorName: "Friend",
                     recordedAt: Date(timeIntervalSince1970: 1_700_000_000), localURL: url,
                     overlayText: captions.firstText, captionSticker: .default,
                     captionsJSON: String(decoding: try JSONEncoder().encode(captions), as: UTF8.self))
    }

    func testColdStartOfflineRestoresPlayableVideoAndAllCaptionsBeforeFetching() async throws {
        let original = try await clip(realVideo: true)
        XCTAssertEqual(original.captions.count, 2)
        clips = [original]
        await store(service()).syncRoom(room.id)
        offline = true
        fetchCount = 0
        let relaunched = store(service())
        XCTAssertEqual(fetchCount, 0)
        let restored = try XCTUnwrap(relaunched.recordedClips(for: room.id).first)
        XCTAssertEqual(restored.authorID, original.authorID)
        XCTAssertEqual(restored.authorName, original.authorName)
        XCTAssertEqual(restored.recordedAt, original.recordedAt)
        XCTAssertEqual(restored.captions, original.captions)
        let duration = try await AVURLAsset(url: restored.url).load(.duration).seconds
        XCTAssertGreaterThan(duration, 1)
        await relaunched.syncRoom(room.id)
        XCTAssertEqual(relaunched.recordedClips(for: room.id).first?.captions, original.captions)
        XCTAssertNotNil(relaunched.syncError(for: room.id))
    }

    func testCaptionOnlyRefreshAndSuccessfulDeletionReplaceTheSnapshot() async throws {
        let original = try await clip()
        clips = [original]
        let sync = service()
        _ = await sync.syncClips(code: "ROOM")
        let edited = CloudKitService.RemoteClip(
            id: original.id, day: original.day, authorID: original.authorID, authorName: original.authorName,
            recordedAt: original.recordedAt, localURL: original.localURL, overlayText: "Edited",
            captionsJSON: Caption.cloudJSON([Caption(text: "Edited")]))
        clips = [edited]
        _ = await sync.syncClips(code: "ROOM")
        XCTAssertEqual(store(service()).recordedClips(for: room.id).first?.captions.first?.text, "Edited")
        clips = []
        _ = await sync.syncClips(code: "ROOM")
        XCTAssertTrue(store(service()).recordedClips(for: room.id).isEmpty)
    }

    func testMissingVideoIsNotRestoredAndSnapshotPathsSurviveDirectoryMove() async throws {
        clips = [try await clip()]
        _ = await service().syncClips(code: "ROOM")
        let oldRoot = files.root
        let movedRoot = oldRoot.appendingPathExtension("moved")
        try FileManager.default.moveItem(at: oldRoot, to: movedRoot)
        files = OfflineRoomFiles(root: movedRoot)
        let moved = try XCTUnwrap(store(service()).recordedClips(for: room.id).first)
        XCTAssertTrue(moved.url.path.hasPrefix(movedRoot.path))
        try FileManager.default.removeItem(at: moved.url)
        XCTAssertTrue(store(service()).recordedClips(for: room.id).isEmpty)
    }

    func testSnapshotDoesNotCrossAccountsOrResurrectAfterLeaving() async throws {
        clips = [try await clip()]
        comments = [.init(id: "private", day: 1, text: "Private", authorID: "me", authorName: "Me", targetAuthorID: "friend", createdAt: .now)]
        let sync = service()
        _ = await sync.syncClips(code: "ROOM")
        _ = await sync.fetchInteractions(code: "ROOM")
        owner = "account-b"
        let otherAccount = service()
        XCTAssertTrue(store(otherAccount).recordedClips(for: room.id).isEmpty)
        XCTAssertNil(otherAccount.remoteComments["ROOM"])
        owner = "account-a"
        XCTAssertEqual(store(service()).recordedClips(for: room.id).count, 1)
        sync.clearRoom("ROOM")
        XCTAssertTrue(store(service()).recordedClips(for: room.id).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.remoteCacheDir(roomCode: "ROOM").path))
    }

    func testHTTPRefreshKeepsOldVideoWhenNewDownloadFailsAndAppliesCaptionOnlyUpdates() async throws {
        let original = try await clip()
        let directory = files.remoteCacheDir(roomCode: "ROOM")
        try RoomContentCache.saveClips([original], in: directory, accountID: AccountStore.persistedUserID)
        try RoomClipCache.saveManifest(.init(versions: [original.id: "tag:old-key"]), in: directory)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineClipProtocol.self]
        let session = URLSession(configuration: config)
        let previous = OneDayAPI.shared
        OneDayAPI.shared = OneDayAPI(baseURL: URL(string: "https://offline.test")!, session: session,
                                    fixedSession: .init(token: "test", userId: "me", expiresAt: .distantFuture))
        defer { OneDayAPI.shared = previous; session.invalidateAndCancel() }
        func payload(_ key: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["clips": [[
                "id": original.id, "day": 1, "authorID": "friend", "authorName": "Friend",
                "recordedAt": 1_700_000_000_000 as Int64, "videoKey": key, "overlayText": "Edited on server"
            ]]])
        }
        OfflineClipProtocol.payload = try payload("new-key")
        let failedDownload = try await CloudKitService.fetchClips(code: "ROOM", into: directory)
        XCTAssertEqual(failedDownload.first?.captions, original.captions)
        XCTAssertEqual(RoomClipCache.loadManifest(in: directory).versions[original.id], "tag:old-key")

        OfflineClipProtocol.payload = try payload("old-key")
        let captionOnly = try await CloudKitService.fetchClips(code: "ROOM", into: directory)
        XCTAssertEqual(captionOnly.first?.captions.first?.text, "Edited on server")
        XCTAssertEqual(try Data(contentsOf: original.localURL), Data([1, 2, 3]))

        OfflineClipProtocol.payload = Data(#"{"clips":[]}"#.utf8)
        let deleted = try await CloudKitService.fetchClips(code: "ROOM", into: directory)
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.localURL.path))
    }

    func testCorruptIndexDoesNotRemoveVideoAndCanBeRebuilt() async throws {
        let original = try await clip()
        clips = [original]
        _ = await service().syncClips(code: "ROOM")
        try Data("broken".utf8).write(to: files.remoteCacheDir(roomCode: "ROOM").appendingPathComponent("clips.json"))
        XCTAssertTrue(store(service()).recordedClips(for: room.id).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.localURL.path))
        _ = await service().syncClips(code: "ROOM")
        XCTAssertEqual(store(service()).recordedClips(for: room.id).count, 1)
    }

    func testSameServiceClearsRestoredMemoryWhenCredentialsAreRevoked() async throws {
        clips = [try await clip()]
        comments = [.init(id: "private", day: 1, text: "Private", authorID: "me", authorName: "Me", targetAuthorID: "friend", createdAt: .now)]
        let sync = service()
        await store(sync).syncRoom(room.id)
        XCTAssertEqual(sync.remoteClips["ROOM"]?.count, 1)
        XCTAssertEqual(sync.remoteComments["ROOM"]?.count, 1)
        owner = nil
        sync.reconcileCacheAccount()
        XCTAssertNil(sync.remoteClips["ROOM"])
        XCTAssertNil(sync.remoteComments["ROOM"])
        owner = "account-b"
        sync.restoreCachedContent(code: "ROOM")
        XCTAssertNil(sync.remoteClips["ROOM"])
        XCTAssertNil(sync.remoteComments["ROOM"])
    }

    func testLaggingFetchPreservesConfirmedWritesAndDoesNotResurrectConfirmedDeletes() async throws {
        let sync = service()
        await sync.postComment(code: "ROOM", day: 1, id: "sent", text: "Sent", authorID: "me", authorName: "Me", targetAuthorID: "friend")
        await sync.setReaction(code: "ROOM", day: 1, authorID: "me", authorName: "Me", targetAuthorID: "friend", emoji: "❤️", on: true)
        let lagging = await sync.fetchInteractions(code: "ROOM")
        XCTAssertEqual(lagging?.comments.map(\.id), ["sent"])
        let relaunched = service()
        _ = store(relaunched)
        XCTAssertEqual(relaunched.remoteComments["ROOM"]?.map(\.id), ["sent"])
        XCTAssertEqual(relaunched.remoteReactions["ROOM"]?.count, 1)
        comments = lagging?.comments ?? []
        reactions = lagging?.reactions ?? []
        await sync.deleteComment(id: "sent", code: "ROOM")
        await sync.setReaction(code: "ROOM", day: 1, authorID: "me", authorName: "Me", targetAuthorID: "friend", emoji: "❤️", on: false)
        let stale = await sync.fetchInteractions(code: "ROOM")
        XCTAssertEqual(stale?.comments.count, 0)
        XCTAssertEqual(stale?.reactions.count, 0)
        let saved = try XCTUnwrap(RoomContentCache.loadInteractions(in: files.remoteCacheDir(roomCode: "ROOM"), accountID: owner))
        let expired = saved.refreshing(with: .init(reactions: reactions, comments: comments),
                                      now: Date().addingTimeInterval(RoomContentCache.confirmationGrace + 1))
        XCTAssertEqual(expired.comments.count, 1)
        XCTAssertEqual(expired.reactions.count, 1)
    }

    func testInitialAccountReconciliationClearsRevocationBeforeUIObservesIdentity() async throws {
        clips = [try await clip()]
        let sync = service()
        _ = await sync.syncClips(code: "ROOM")
        let launched = store(sync)
        XCTAssertEqual(launched.recordedClips(for: room.id).count, 1)
        owner = nil
        await launched.reconcileAccountRooms()
        XCTAssertTrue(launched.recordedClips(for: room.id).isEmpty)
        XCTAssertNil(sync.remoteClips["ROOM"])
    }

    func testInteractionsSurviveOfflineRelaunchAndConfirmedRemoval() async throws {
        reactions = [.init(day: 1, emoji: "❤️", authorID: "me", authorName: "Me", targetAuthorID: "friend", createdAt: .now)]
        comments = [.init(id: "comment", day: 1, text: "Hello 🌙", authorID: "me", authorName: "Me", targetAuthorID: "friend", createdAt: .now)]
        let sync = service()
        _ = await sync.fetchInteractions(code: "ROOM")
        offline = true
        let relaunched = service()
        _ = store(relaunched)
        XCTAssertEqual(relaunched.remoteReactions["ROOM"]?.first?.emoji, "❤️")
        XCTAssertEqual(relaunched.remoteComments["ROOM"]?.first?.text, "Hello 🌙")
        let failed = await relaunched.fetchInteractions(code: "ROOM")
        XCTAssertNil(failed)
        XCTAssertEqual(relaunched.remoteComments["ROOM"]?.count, 1)
        offline = false
        reactions = []; comments = []
        _ = await sync.fetchInteractions(code: "ROOM")
        let afterDeletion = service()
        _ = store(afterDeletion)
        XCTAssertEqual(afterDeletion.remoteReactions["ROOM"]?.count, 0)
        XCTAssertEqual(afterDeletion.remoteComments["ROOM"]?.count, 0)
    }

    func testOnlyConfirmedInteractionWritesAreDurable() async throws {
        let sync = service()
        await sync.setReaction(code: "ROOM", day: 1, authorID: "me", authorName: "Me", targetAuthorID: "friend", emoji: "❤️", on: true)
        await sync.postComment(code: "ROOM", day: 1, id: "sent", text: "Sent", authorID: "me", authorName: "Me", targetAuthorID: "friend")
        offline = true
        await sync.postComment(code: "ROOM", day: 1, id: "failed", text: "Not sent", authorID: "me", authorName: "Me", targetAuthorID: "friend")
        let relaunched = service()
        _ = store(relaunched)
        XCTAssertEqual(relaunched.remoteComments["ROOM"]?.map(\.id), ["sent"])
        XCTAssertEqual(relaunched.remoteReactions["ROOM"]?.count, 1)
        offline = false
        await sync.deleteComment(id: "sent", code: "ROOM")
        await sync.setReaction(code: "ROOM", day: 1, authorID: "me", authorName: "Me", targetAuthorID: "friend", emoji: "❤️", on: false)
        let afterRemoval = service()
        _ = store(afterRemoval)
        XCTAssertEqual(afterRemoval.remoteComments["ROOM"]?.count, 0)
        XCTAssertEqual(afterRemoval.remoteReactions["ROOM"]?.count, 0)
    }

    func testLateClipResponseCannotRecreateCacheAfterLeaving() async throws {
        let original = try await clip()
        var continuation: CheckedContinuation<[CloudKitService.RemoteClip], Never>?
        var transport = transport()
        transport.fetchClips = { _, _ in await withCheckedContinuation { continuation = $0 } }
        let sync = service(transport: transport)
        let request = Task { await sync.syncClips(code: "ROOM") }
        while continuation == nil { await Task.yield() }
        sync.clearRoom("ROOM")
        continuation?.resume(returning: [original])
        let result = await request.value
        XCTAssertNil(result)
        XCTAssertNil(sync.remoteClips["ROOM"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.remoteCacheDir(roomCode: "ROOM").path))
    }

    func testOlderInteractionFetchCannotOverwriteConfirmedMutation() async {
        var continuation: CheckedContinuation<([CloudKitService.RemoteReaction], [CloudKitService.RemoteComment]), Never>?
        var transport = transport()
        transport.fetchInteractions = { _ in await withCheckedContinuation { continuation = $0 } }
        let sync = service(transport: transport)
        let request = Task { await sync.fetchInteractions(code: "ROOM") }
        while continuation == nil { await Task.yield() }
        await sync.postComment(code: "ROOM", day: 1, id: "sent", text: "Sent", authorID: "me", authorName: "Me", targetAuthorID: "friend")
        continuation?.resume(returning: ([], []))
        _ = await request.value
        let relaunched = service()
        _ = store(relaunched)
        XCTAssertEqual(relaunched.remoteComments["ROOM"]?.map(\.id), ["sent"])
    }
}

private final class OfflineClipProtocol: URLProtocol {
    static var payload = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.path.hasSuffix("/clips") else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class OfflineRoomRepository: ChallengeRepository {
    var rooms: [Challenge]
    init(rooms: [Challenge]) { self.rooms = rooms }
    func loadChallenges() -> [Challenge] { rooms }
    func saveChallenges(_ challenges: [Challenge]) { rooms = challenges }
}

private final class OfflineRoomFiles: ClipFileStore {
    let root: URL
    init(root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("offline-room-\(UUID())")) {
        self.root = root
    }
    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? { nil }
    func clipURL(fileName: String, challengeID: UUID) -> URL { root.appendingPathComponent(fileName) }
    func deleteClips(challengeID: UUID) {}
    func remoteCacheDir(roomCode: String) -> URL { root.appendingPathComponent(roomCode) }
    func deleteRemoteCache(roomCode: String) { try? FileManager.default.removeItem(at: remoteCacheDir(roomCode: roomCode)) }
    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {}
}
