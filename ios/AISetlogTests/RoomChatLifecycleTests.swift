import XCTest
@testable import AISetlog

// Test-only convenience: production callers must supply an identity lease.
@MainActor
extension RoomChatSession {
    convenience init(scope: RoomChatScope, directory: URL, transport: any RoomChatTransport) {
        self.init(scope: scope, directory: directory, transport: transport, identityIsCurrent: { true })
    }
}

@MainActor
final class RoomChatLifecycleTests: XCTestCase {
    private final class Transport: RoomChatTransport {
        var onSend: (() -> Void)?
        var onFetch: (() -> Void)?
        var sends = 0
        var missingLookups = 0
        func fetch(roomCode: String) async throws -> [RoomChatMessage] { onFetch?(); return [] }
        func send(_ message: RoomChatMessage) async throws { sends += 1; onSend?() }
        func delete(_ message: RoomChatMessage, accountID: String) async throws { }
        func confirmedMissing(_ ids: Set<UUID>, roomCode: String) async throws -> Set<UUID> {
            missingLookups += 1
            return ids
        }
    }

    func testLateSendAfterSignOutDoesNotAcknowledgeOrRewriteArchive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = RoomChatScope(accountID: "alice", roomCode: "ABCDEF")
        let transport = Transport()
        var current = true
        let session = RoomChatSession(scope: scope, directory: directory, transport: transport, identityIsCurrent: { current })
        session.setDraft("pending")
        transport.onSend = { current = false }
        await session.send(authorName: "Alice")
        XCTAssertNil(session.state)
        let restored = RoomChatSession(scope: scope, directory: directory, transport: transport)
        XCTAssertEqual(restored.state?.entries.first?.delivery, .failed)
        XCTAssertEqual(restored.state?.entries.first?.message.text, "pending")
        session.setDraft("must not write")
        await session.send(authorName: "Alice")
        XCTAssertEqual(transport.sends, 1)
    }

    func testLateRefreshCannotDeleteOrOverwriteAfterAccountSwitch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scope = RoomChatScope(accountID: "alice", roomCode: "ABCDEF")
        let transport = Transport()
        var current = true
        let session = RoomChatSession(scope: scope, directory: directory, transport: transport, identityIsCurrent: { current })
        session.setDraft("hello")
        await session.send(authorName: "Alice")
        transport.onFetch = { current = false }
        await session.refresh()
        XCTAssertNil(session.state)
        XCTAssertEqual(transport.missingLookups, 0)
        let restored = RoomChatSession(scope: scope, directory: directory, transport: transport)
        XCTAssertEqual(restored.state?.entries.count, 1)
        XCTAssertEqual(restored.state?.entries.first?.delivery, .sent)
    }

    func testInvalidLeaseDoesNotCreateOrSendDraft() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = Transport()
        let session = RoomChatSession(scope: .init(accountID: "alice", roomCode: "ABCDEF"), directory: directory,
                                      transport: transport, identityIsCurrent: { false })
        XCTAssertNil(session.state) // Even initial archive loading requires a valid lease.
        session.setDraft("must not persist")
        await session.send(authorName: "Alice")
        XCTAssertNil(session.state)
        XCTAssertEqual(transport.sends, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testIdentityRevisionChangesForSignOutButNotRename() {
        let original = UserDefaults.standard.object(forKey: "account.v1")
        defer {
            if let original { UserDefaults.standard.set(original, forKey: "account.v1") }
            else { UserDefaults.standard.removeObject(forKey: "account.v1") }
        }
        let account = AccountStore()
        account.signInAsTester(named: "Alice")
        let signedInRevision = AccountStore.identityRevision
        account.rename(to: "Alice renamed")
        XCTAssertEqual(AccountStore.identityRevision, signedInRevision)
        account.signOut()
        XCTAssertNotEqual(AccountStore.identityRevision, signedInRevision)
        XCTAssertNil(AccountStore.persistedUserID)
    }
}
