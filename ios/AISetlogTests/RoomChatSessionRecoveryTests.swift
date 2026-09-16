import XCTest
@testable import AISetlog

@MainActor
final class RoomChatSessionRecoveryTests: XCTestCase {
    private final class Transport: RoomChatTransport {
        var sends: [RoomChatMessage] = []
        var fetches = 0
        func fetch(roomCode: String) async throws -> [RoomChatMessage] { fetches += 1; return [] }
        func send(_ message: RoomChatMessage) async throws { sends.append(message) }
        func delete(_ message: RoomChatMessage, accountID: String) async throws { XCTFail("unexpected delete") }
        func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID> { [] }
    }
    private let scope = RoomChatScope(accountID: "alice", roomCode: "LOCAL")
    private func candidate() -> LegacyRoomChatMigration.Candidate {
        .init(comment: ClipComment(id: UUID(), text: "  用户原文  ", authorID: "alice", authorName: "Alice", createdAt: Date()),
              roomCode: "LOCAL", moment: 1, evidence: .confirmedNeverUploaded)
    }

    func testSessionRecoveryPersistsWithoutSendingAndManualRetryKeepsIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = Transport()
        let session = RoomChatSession(scope: scope, directory: directory, transport: transport, identityIsCurrent: { true })
        session.setDraft("draft")
        let old = candidate()
        XCTAssertNotNil(session.recoverLegacyComments([old]))
        XCTAssertTrue(transport.sends.isEmpty)
        XCTAssertEqual(transport.fetches, 0)
        XCTAssertEqual(session.state?.draft, "draft")
        let restored = RoomChatSession(scope: scope, directory: directory, transport: transport, identityIsCurrent: { true })
        XCTAssertEqual(restored.state, session.state)
        XCTAssertTrue(try XCTUnwrap(restored.recoverLegacyComments([old])).recoverable.isEmpty)
        await restored.retry(old.message.id)
        XCTAssertEqual(transport.sends, [old.message])
        XCTAssertEqual(restored.state?.entries.first?.delivery, .sent)
    }

    func testInvalidIdentityCannotRecoverOrWriteArchive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var valid = true
        let session = RoomChatSession(scope: scope, directory: directory, transport: Transport(), identityIsCurrent: { valid })
        valid = false
        XCTAssertNil(session.recoverLegacyComments([candidate()]))
        XCTAssertNil(session.state)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDiskFailureRetainsVisibleStateAndReportsStorageFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = RoomChatSession(scope: scope, directory: directory, transport: Transport(), identityIsCurrent: { true })
        let before = session.state
        // A file where a directory belongs deterministically rejects archive save.
        try Data("block directory".utf8).write(to: directory)
        XCTAssertNil(session.recoverLegacyComments([candidate()]))
        XCTAssertEqual(session.state, before)
        XCTAssertEqual(session.error, .storage)
        XCTAssertEqual(try Data(contentsOf: directory), Data("block directory".utf8))
    }
}
