import XCTest
@testable import AISetlog

/// Deterministic races at the real session/archive boundary; no CloudKit calls.
@MainActor
final class RoomChatConcurrencyTests: XCTestCase {
    private final class Transport: RoomChatTransport {
        enum Failure: Error { case permission }
        var fetchStarted: (() -> Void)?
        var pendingFetch: CheckedContinuation<[RoomChatMessage], Error>?
        var missingRequests: [Set<UUID>] = []
        var failMissing = false
        var messages: [RoomChatMessage] = []
        var suspendFetch = false
        func fetch(roomCode: String) async throws -> [RoomChatMessage] {
            if suspendFetch {
                return try await withCheckedThrowingContinuation { continuation in
                    pendingFetch = continuation
                    fetchStarted?()
                }
            }
            return messages
        }
        func send(_ message: RoomChatMessage) async throws { messages.append(message) }
        func delete(_ message: RoomChatMessage, accountID: String) async throws {
            messages.removeAll { $0.id == message.id }
        }
        func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID> {
            missingRequests.append(ids)
            if failMissing { throw Failure.permission }
            return ids
        }
        func resume(_ snapshot: [RoomChatMessage]) {
            let continuation = pendingFetch
            pendingFetch = nil
            continuation?.resume(returning: snapshot)
        }
    }

    func testFetchStartedBeforeSendCannotTombstoneNewAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = Transport()
        transport.suspendFetch = true
        let started = expectation(description: "fetch suspended")
        transport.fetchStarted = { started.fulfill() }
        let scope = RoomChatScope(accountID: "alice", roomCode: "ABCDEF")
        let session = RoomChatSession(scope: scope, directory: directory, transport: transport)
        let refresh = Task { await session.refresh() }
        await fulfillment(of: [started], timeout: 2)
        session.setDraft("sent after snapshot began")
        await session.send(authorName: "Alice")
        let id = try XCTUnwrap(session.state?.entries.first?.id)
        transport.resume([])
        await refresh.value
        XCTAssertTrue(transport.missingRequests.isEmpty)
        XCTAssertEqual(session.state?.entries.first?.delivery, .sent)
        XCTAssertFalse(session.state?.deletedIDs.contains(id) ?? true)
        let restored = RoomChatSession(scope: scope, directory: directory, transport: transport)
        XCTAssertEqual(restored.state?.entries.first?.id, id)
    }

    func testDeleteDuringFetchRejectsStaleSnapshotAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = Transport()
        let scope = RoomChatScope(accountID: "alice", roomCode: "ABCDEF")
        let session = RoomChatSession(scope: scope, directory: directory, transport: transport)
        session.setDraft("delete while refresh is pending")
        await session.send(authorName: "Alice")
        let message = try XCTUnwrap(session.state?.entries.first?.message)
        transport.suspendFetch = true
        let started = expectation(description: "fetch suspended")
        transport.fetchStarted = { started.fulfill() }
        let refresh = Task { await session.refresh() }
        await fulfillment(of: [started], timeout: 2)
        await session.delete(message.id)
        transport.resume([message])
        await refresh.value
        XCTAssertTrue(session.state?.entries.isEmpty == true)
        let restored = RoomChatSession(scope: scope, directory: directory, transport: transport)
        XCTAssertTrue(restored.state?.entries.isEmpty == true)
        XCTAssertTrue(restored.state?.deletedIDs.contains(message.id) == true)
    }

    func testPermissionFailureInDirectLookupPreservesArchiveAndDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = Transport()
        let scope = RoomChatScope(accountID: "alice", roomCode: "ABCDEF")
        let session = RoomChatSession(scope: scope, directory: directory, transport: transport)
        session.setDraft("confirmed message")
        await session.send(authorName: "Alice")
        let id = try XCTUnwrap(session.state?.entries.first?.id)
        session.setDraft("未完成 mixed text")
        transport.messages = []
        transport.failMissing = true
        await session.refresh()
        XCTAssertEqual(session.error, .fetch)
        XCTAssertEqual(transport.missingRequests, [Set([id])])
        let restored = RoomChatSession(scope: scope, directory: directory, transport: transport)
        XCTAssertEqual(restored.state?.entries.first?.id, id)
        XCTAssertEqual(restored.state?.draft, "未完成 mixed text")
        XCTAssertTrue(restored.state?.deletedIDs.isEmpty == true)
        transport.failMissing = false
        await session.refresh()
        XCTAssertNil(session.error)
        XCTAssertTrue(session.state?.entries.isEmpty == true)
    }

    func testSameAccountDifferentRoomsKeepDraftsAndOutboxSeparate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = Transport()
        let first = RoomChatScope(accountID: "alice", roomCode: "ABCDEF")
        let second = RoomChatScope(accountID: "alice", roomCode: "UVWXYZ")
        let a = RoomChatSession(scope: first, directory: directory, transport: transport)
        let b = RoomChatSession(scope: second, directory: directory, transport: transport)
        a.setDraft("room one")
        await a.send(authorName: "Alice", moment: 3)
        a.setDraft("draft one")
        b.setDraft("draft two")
        let restoredA = RoomChatSession(scope: first, directory: directory, transport: transport)
        let restoredB = RoomChatSession(scope: second, directory: directory, transport: transport)
        XCTAssertEqual(restoredA.state?.draft, "draft one")
        XCTAssertEqual(restoredA.state?.entries.first?.message.moment, 3)
        XCTAssertEqual(restoredB.state?.draft, "draft two")
        XCTAssertTrue(restoredB.state?.entries.isEmpty == true)
    }
}
