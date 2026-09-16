import XCTest
@testable import AISetlog

@MainActor
final class RoomChatDemoTests: XCTestCase {
    func testSamplesContainBothSidesLongTextAndMomentContext() async throws {
        let demo = RoomChatDemoTransport(chinese: true)
        defer { demo.close() }
        let messages = try await demo.fetch(roomCode: demo.scope.roomCode)
        XCTAssertEqual(messages.count, 6)
        XCTAssertEqual(Set(messages.map(\.authorID)), ["demo-me", "demo-friend"])
        XCTAssertTrue(messages.contains { $0.text.contains("\n") })
        XCTAssertTrue(messages.contains { $0.moment != nil })
        XCTAssertTrue(messages.allSatisfy { $0.roomCode == demo.scope.roomCode })
    }

    func testDemoRejectsRealRoomScope() async {
        let demo = RoomChatDemoTransport(chinese: false)
        defer { demo.close() }
        do {
            _ = try await demo.fetch(roomCode: "ABCDEF")
            XCTFail("Demo must reject a real room")
        } catch { }
    }

    func testSendRetryAndDeleteAreLocalAndIdempotent() async throws {
        let demo = RoomChatDemoTransport(chinese: false)
        defer { demo.close() }
        let message = RoomChatMessage(id: UUID(), roomCode: demo.scope.roomCode,
            authorID: demo.scope.accountID, authorName: "Me (demo)", text: "Try this", createdAt: Date(), moment: nil)
        try await demo.send(message)
        try await demo.send(message)
        let sent = try await demo.fetch(roomCode: demo.scope.roomCode)
        XCTAssertEqual(sent.filter { $0.id == message.id }.count, 1)
        try await demo.delete(message, accountID: demo.scope.accountID)
        let missing = try await demo.confirmedMissing([message.id], roomCode: demo.scope.roomCode)
        XCTAssertEqual(missing, [message.id])
    }

    func testExitRemovesTemporaryDraftAndInvalidatesSession() async throws {
        let demo = RoomChatDemoTransport(chinese: true)
        let session = RoomChatSession(scope: demo.scope, directory: demo.directory,
                                      transport: demo, identityIsCurrent: { !demo.isClosed })
        session.setDraft("Only temporary")
        XCTAssertTrue(FileManager.default.fileExists(atPath: demo.directory.path))
        demo.close()
        session.setDraft("Must not recreate archive")
        await session.refresh()
        XCTAssertNil(session.state)
        XCTAssertFalse(FileManager.default.fileExists(atPath: demo.directory.path))
    }

    func testEnglishDemoUsesEnglishSamples() async throws {
        let demo = RoomChatDemoTransport(chinese: false)
        defer { demo.close() }
        let messages = try await demo.fetch(roomCode: demo.scope.roomCode)
        XCTAssertEqual(messages.first?.text, "What should we film today?")
        XCTAssertEqual(messages.first?.authorName, "Sample friend")
    }
}
