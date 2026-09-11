import XCTest
@testable import AISetlog

@MainActor
final class RoomChatSessionTests: XCTestCase {
    private final class FakeTransport: RoomChatTransport {
        enum Failure: Error { case offline }
        var failSend = false
        var failFetch = false
        var failDelete = false
        var missing: Set<UUID> = []
        var deleted: [UUID] = []
        var sent: [RoomChatMessage] = []
        var fetched: [RoomChatMessage] = []
        func fetch(roomCode: String) async throws -> [RoomChatMessage] {
            if failFetch { throw Failure.offline }
            return fetched
        }
        func send(_ message: RoomChatMessage) async throws {
            sent.append(message)
            if failSend { throw Failure.offline }
        }
        func delete(_ message: RoomChatMessage, accountID: String) async throws {
            if failDelete { throw Failure.offline }
            deleted.append(message.id)
        }
        func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID> {
            missing.intersection(ids)
        }
    }

    func testFailedSendRetryReusesDurableMessage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FakeTransport()
        transport.failSend = true
        let scope = RoomChatScope(accountID: "alice", roomCode: "ABCDEF")
        let session = RoomChatSession(scope: scope, directory: directory, transport: transport)
        session.setDraft("hello")
        await session.send(authorName: "Alice")
        XCTAssertEqual(session.state?.entries.first?.delivery, .failed)
        let restored = RoomChatSession(scope: scope, directory: directory, transport: transport)
        let id = try XCTUnwrap(restored.state?.entries.first?.id)
        transport.failSend = false
        await restored.retry(id)
        XCTAssertEqual(transport.sent.map(\.id), [id, id])
        XCTAssertEqual(restored.state?.entries.first?.delivery, .sent)
    }

    func testFailedFetchDoesNotClearMessagesOrDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FakeTransport()
        let session = RoomChatSession(scope: .init(accountID: "alice", roomCode: "ABCDEF"),
                                      directory: directory, transport: transport)
        session.setDraft("hello")
        await session.send(authorName: "Alice")
        session.setDraft("unfinished")
        transport.failFetch = true
        await session.refresh()
        XCTAssertEqual(session.state?.entries.count, 1)
        XCTAssertEqual(session.state?.draft, "unfinished")
        XCTAssertEqual(session.error, .fetch)
    }

    func testDeleteFailureKeepsMessageAndSuccessSurvivesStaleFetch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FakeTransport()
        let scope = RoomChatScope(accountID: "alice", roomCode: "ABCDEF")
        let session = RoomChatSession(scope: scope, directory: directory, transport: transport)
        session.setDraft("hello")
        await session.send(authorName: "Alice")
        let message = try XCTUnwrap(session.state?.entries.first?.message)
        transport.failDelete = true
        await session.delete(message.id)
        XCTAssertEqual(session.state?.entries.count, 1)
        XCTAssertEqual(session.error, .delete)
        transport.failDelete = false
        await session.delete(message.id)
        XCTAssertEqual(transport.deleted, [message.id])
        XCTAssertTrue(session.state?.entries.isEmpty == true)
        transport.fetched = [message]
        await session.refresh()
        XCTAssertTrue(session.state?.entries.isEmpty == true)
        let restored = RoomChatSession(scope: scope, directory: directory, transport: transport)
        await restored.refresh()
        XCTAssertTrue(restored.state?.entries.isEmpty == true)
    }

    func testConfirmedRemoteDeletionRemovedButCannotDeleteFriendsMessage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FakeTransport()
        let message = RoomChatMessage(id: UUID(), roomCode: "ABCDEF", authorID: "bob", authorName: "Bob",
                                      text: "hello", createdAt: Date(), moment: nil)
        transport.fetched = [message]
        let session = RoomChatSession(scope: .init(accountID: "alice", roomCode: "ABCDEF"), directory: directory, transport: transport)
        await session.refresh()
        await session.delete(message.id)
        XCTAssertTrue(transport.deleted.isEmpty)
        transport.fetched = []
        await session.refresh()
        XCTAssertEqual(session.state?.entries.count, 1) // Query omission alone is insufficient.
        transport.missing = [message.id]
        await session.refresh()
        XCTAssertTrue(session.state?.entries.isEmpty == true)
    }

    func testOversizedMessagePreservesDraftAndDoesNotSend() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FakeTransport()
        let session = RoomChatSession(scope: .init(accountID: "alice", roomCode: "ABCDEF"), directory: directory, transport: transport)
        let draft = String(repeating: "好", count: 2_001)
        session.setDraft(draft)
        await session.send(authorName: "Alice")
        XCTAssertEqual(session.state?.draft, draft)
        XCTAssertEqual(session.error, .messageTooLong)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testDifferentAccountsUseDifferentArchives() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FakeTransport()
        let alice = RoomChatSession(scope: .init(accountID: "alice", roomCode: "ABCDEF"), directory: directory, transport: transport)
        alice.setDraft("private draft")
        let bob = RoomChatSession(scope: .init(accountID: "bob", roomCode: "ABCDEF"), directory: directory, transport: transport)
        XCTAssertEqual(bob.state?.draft, "")
    }

    func testStorageFailureDoesNotSendOrLoseComposerText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = FakeTransport()
        let session = RoomChatSession(scope: .init(accountID: "alice", roomCode: "ABCDEF"), directory: directory, transport: transport)
        // A regular file blocks creation of the archive directory.
        try Data("blocked".utf8).write(to: directory)
        session.setDraft("keep me")
        await session.send(authorName: "Alice")
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(session.state?.draft, "keep me")
        XCTAssertEqual(session.error, .storage)
    }
}
