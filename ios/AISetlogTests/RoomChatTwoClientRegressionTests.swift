import XCTest
@testable import AISetlog

/// Two real session/archive clients; the server is deliberately local and injectable.
@MainActor
final class RoomChatTwoClientRegressionTests: XCTestCase {
    private final class Server: RoomChatTransport {
        enum Failure: Error { case offline, acknowledgementLost, permission }
        var records: [UUID: RoomChatMessage] = [:]
        var offline = false
        var loseNextAcknowledgement = false
        var denyDelete = false
        var sendIDs: [UUID] = []
        var deleteCalls = 0
        var staleSnapshot: [RoomChatMessage]?

        func fetch(roomCode: String) async throws -> [RoomChatMessage] {
            if offline { throw Failure.offline }
            return (staleSnapshot ?? Array(records.values)).filter { $0.roomCode == roomCode }
        }
        func send(_ message: RoomChatMessage) async throws {
            sendIDs.append(message.id)
            if offline { throw Failure.offline }
            records[message.id] = message
            if loseNextAcknowledgement {
                loseNextAcknowledgement = false
                throw Failure.acknowledgementLost
            }
        }
        func delete(_ message: RoomChatMessage, accountID: String) async throws {
            deleteCalls += 1
            if offline { throw Failure.offline }
            guard !denyDelete, records[message.id]?.authorID == accountID else { throw Failure.permission }
            records.removeValue(forKey: message.id)
        }
        func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID> {
            if offline { throw Failure.offline }
            return ids.filter { records[$0] == nil }
        }
    }

    func testOfflineRestartAndLostAcknowledgementConvergeWithoutDuplicate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = Server()
        let scope = RoomChatScope(accountID: "alice", roomCode: "ABCDEF")
        var alice: RoomChatSession? = RoomChatSession(scope: scope, directory: root, transport: server, identityIsCurrent: { true })
        let bob = RoomChatSession(scope: .init(accountID: "bob", roomCode: "ABCDEF"), directory: root, transport: server, identityIsCurrent: { true })
        let text = String(repeating: "好", count: 1_990) + " hello 🌱"
        server.offline = true
        alice?.setDraft(text)
        await alice?.send(authorName: "Alice", moment: 3)
        let original = try XCTUnwrap(alice?.state?.entries.first?.message)
        XCTAssertEqual(alice?.state?.entries.first?.delivery, .failed)
        alice?.setDraft("next private draft")
        alice = nil
        let restored = RoomChatSession(scope: scope, directory: root, transport: server, identityIsCurrent: { true })
        XCTAssertEqual(restored.state?.draft, "next private draft")
        XCTAssertEqual(bob.state?.draft, "")
        server.offline = false
        server.loseNextAcknowledgement = true
        await restored.retry(original.id)
        XCTAssertEqual(restored.state?.entries.first?.delivery, .failed)
        await bob.refresh()
        XCTAssertEqual(bob.state?.entries.map(\.message), [original])
        await restored.retry(original.id)
        await bob.refresh()
        await restored.refresh()
        XCTAssertEqual(server.sendIDs, [original.id, original.id, original.id])
        XCTAssertEqual(server.records.count, 1)
        XCTAssertEqual(restored.state?.entries.map(\.message), [original])
        XCTAssertEqual(restored.state?.entries.first?.delivery, .sent)
        XCTAssertEqual(bob.state?.entries.map(\.message), [original])
        XCTAssertEqual(restored.state?.draft, "next private draft")
    }

    func testAuthorPermissionFailureThenPeerDeletionSurvivesRestartAndStaleSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = Server()
        let alice = RoomChatSession(scope: .init(accountID: "alice", roomCode: "ABCDEF"), directory: root, transport: server, identityIsCurrent: { true })
        let bobScope = RoomChatScope(accountID: "bob", roomCode: "ABCDEF")
        let bob = RoomChatSession(scope: bobScope, directory: root, transport: server, identityIsCurrent: { true })
        alice.setDraft("whole-room message, no recording required")
        await alice.send(authorName: "Alice")
        let message = try XCTUnwrap(alice.state?.entries.first?.message)
        XCTAssertNil(message.moment)
        await bob.refresh()
        await bob.delete(message.id)
        XCTAssertEqual(server.deleteCalls, 0)
        server.denyDelete = true
        await alice.delete(message.id)
        XCTAssertEqual(alice.error, .delete)
        XCTAssertEqual(alice.state?.entries.count, 1)
        await bob.refresh()
        XCTAssertEqual(bob.state?.entries.count, 1)
        server.denyDelete = false
        await alice.delete(message.id)
        await bob.refresh()
        XCTAssertTrue(bob.state?.entries.isEmpty == true)
        server.staleSnapshot = [message]
        let restored = RoomChatSession(scope: bobScope, directory: root, transport: server, identityIsCurrent: { true })
        await restored.refresh()
        await alice.refresh()
        XCTAssertTrue(restored.state?.entries.isEmpty == true)
        XCTAssertTrue(alice.state?.entries.isEmpty == true)
        XCTAssertEqual(restored.state?.deletedIDs, [message.id])
    }
}
