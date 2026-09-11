import XCTest
@testable import AISetlog

@MainActor
final class RoomSyncIsolationTests: XCTestCase {
    func testDefaultInitializerKeepsCacheAndCleanupBehaviorWithoutNetwork() throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        // Omit transport exactly as ChallengeStore's default-live path does.
        // Construction and cache access must not submit any cloud operation.
        let service = RoomSyncService(fileStore: files)
        XCTAssertEqual(service.remoteCacheDir(for: "ROOM"), files.remoteCacheDir(roomCode: "ROOM"))
        service.remoteClips["ROOM"] = []
        service.remoteComments["ROOM"] = []
        service.clearRoom("ROOM")
        XCTAssertNil(service.remoteClips["ROOM"])
        XCTAssertNil(service.remoteComments["ROOM"])
        XCTAssertTrue(service.syncing.isEmpty)
    }

    func testAllSixOperationsUseInjectedTransportAndPreserveArguments() async throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        var calls: [String] = []
        let url = files.root.appendingPathComponent("fixture.mov")
        let transport = RoomSyncTransport(
            fetchClips: { code, directory in
                XCTAssertEqual(directory, files.remoteCacheDir(roomCode: code))
                calls.append("fetch:\(code)")
                return []
            },
            fetchInteractions: { calls.append("interactions:\($0)"); return ([], []) },
            uploadClip: { code, day, author, name, file, caption in
                XCTAssertEqual([code, author, name, caption ?? ""], ["ROOM", "me", "Me", "mine"])
                XCTAssertEqual(day, 2); XCTAssertEqual(file, url)
                calls.append("upload")
            },
            setReaction: { code, day, author, name, target, emoji, on in
                XCTAssertEqual([code, author, name, target, emoji], ["ROOM", "me", "Me", "friend", "♥"])
                XCTAssertEqual(day, 2); XCTAssertFalse(on)
                calls.append("reaction")
            },
            postComment: { code, day, id, text, author, name, target in
                XCTAssertEqual([code, id, text, author, name, target], ["ROOM", "id", "hello", "me", "Me", "friend"])
                XCTAssertEqual(day, 2); calls.append("comment")
            },
            deleteComment: { XCTAssertEqual($0, "id"); calls.append("delete") })
        let service = RoomSyncService(fileStore: files, transport: transport)
        let clips = await service.syncClips(code: "ROOM")
        XCTAssertEqual(clips?.count, 0)
        let interactions = await service.fetchInteractions(code: "ROOM")
        XCTAssertNotNil(interactions)
        let uploaded = await service.uploadClip(code: "ROOM", day: 2, authorID: "me", authorName: "Me", fileURL: url, overlayText: "mine")
        XCTAssertTrue(uploaded)
        await service.setReaction(code: "ROOM", day: 2, authorID: "me", authorName: "Me", targetAuthorID: "friend", emoji: "♥", on: false)
        await service.postComment(code: "ROOM", day: 2, id: "id", text: "hello", authorID: "me", authorName: "Me", targetAuthorID: "friend")
        await service.deleteComment(id: "id")
        XCTAssertEqual(calls, ["fetch:ROOM", "interactions:ROOM", "upload", "reaction", "comment", "delete"])
        XCTAssertNil(service.lastError["ROOM"])
        XCTAssertTrue(service.syncing.isEmpty)
    }

    func testLocalSourceScopesFixturesRejectsWritesAndClosesOutstandingTransport() async throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        let clip = CloudKitService.RemoteClip(id: "friend-day1", day: 1, authorID: "friend", authorName: "Friend", recordedAt: Date(), localURL: files.root.appendingPathComponent("fixture.mov"), overlayText: "Friend's caption")
        let source = LocalRoomSyncSource(code: "LOCAL", clips: [clip])
        let service = RoomSyncService(fileStore: files, transport: source.transport)
        let clips = await service.syncClips(code: "LOCAL")
        XCTAssertEqual(clips?.map(\.id), [clip.id])
        let unknown = await service.syncClips(code: "REAL")
        XCTAssertNil(unknown)
        let uploaded = await service.uploadClip(code: "LOCAL", day: 1, authorID: "me", authorName: "Me", fileURL: clip.localURL, overlayText: nil)
        XCTAssertFalse(uploaded, "read-only fixtures must not fake cloud confirmation")
        XCTAssertNotNil(service.lastError["LOCAL"])
        source.close()
        let closed = await service.syncClips(code: "LOCAL")
        XCTAssertNil(closed)
        let interactions = await service.fetchInteractions(code: "LOCAL")
        XCTAssertNil(interactions)
        XCTAssertEqual(service.remoteClips["LOCAL"]?.map(\.id), [clip.id], "failure must preserve the last cache, not mean an empty room")
        service.clearRoom("LOCAL")
        XCTAssertNil(service.remoteClips["LOCAL"])
        XCTAssertTrue(service.syncing.isEmpty)
    }

    func testEveryLocalMutationFailsClosed() async throws {
        let source = LocalRoomSyncSource(code: "LOCAL", clips: [])
        let transport = source.transport
        let operations: [() async throws -> Void] = [
            { try await transport.uploadClip("LOCAL", 1, "me", "Me", URL(fileURLWithPath: "/unused"), nil) },
            { try await transport.setReaction("LOCAL", 1, "me", "Me", "friend", "♥", true) },
            { try await transport.postComment("LOCAL", 1, "id", "text", "me", "Me", "friend") },
            { try await transport.deleteComment("id") }
        ]
        for operation in operations {
            do { try await operation(); XCTFail("must reject unsupported mutation") }
            catch LocalRoomSyncSource.Failure.readOnly { }
            catch { XCTFail("unexpected error: \(error)") }
        }
        source.close()
        for operation in operations {
            do { try await operation(); XCTFail("closed session must reject late writes") }
            catch LocalRoomSyncSource.Failure.closed { }
            catch { XCTFail("unexpected error: \(error)") }
        }
    }
}
