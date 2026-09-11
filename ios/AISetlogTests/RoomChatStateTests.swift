import XCTest
#if canImport(AISetlog)
@testable import AISetlog
#endif

final class RoomChatStateTests: XCTestCase {
    private let scope = RoomChatScope(accountID: "alice", roomCode: "ABCDEF")

    func testWholeRoomIncludesDifferentAuthorsAndMoments() throws {
        var state = try RoomChatState(scope: scope)
        let messages = [1, 7].map { (moment: Int) in
            RoomChatMessage(id: UUID(), roomCode: scope.roomCode, authorID: "friend-\(moment)",
                            authorName: "Friend", text: "hello", createdAt: Date(), moment: moment)
        }
        try state.mergeSuccessfulFetch(messages)
        XCTAssertEqual(Set(state.entries.map(\.id)), Set(messages.map(\.id)))
    }

    func testRetryKeepsIDAndEchoDeduplicates() throws {
        var state = try RoomChatState(scope: scope)
        state.draft = "  你好 👋  "
        let message = try state.enqueue(authorName: "Alice")
        XCTAssertEqual(message.text, "你好 👋")
        XCTAssertEqual(state.draft, "")
        state.markFailed(message.id)
        XCTAssertEqual(try state.retry(message.id), message)
        try state.mergeSuccessfulFetch([message, message])
        state.markFailed(message.id)
        XCTAssertEqual(state.entries.count, 1)
        XCTAssertEqual(state.entries.first?.delivery, .sent)
    }

    func testEmptyFetchDoesNotErasePendingOrConfirmedMessages() throws {
        var state = try RoomChatState(scope: scope)
        state.draft = "one"
        let first = try state.enqueue(authorName: "Alice")
        try state.acknowledge(first)
        state.draft = "two"
        _ = try state.enqueue(authorName: "Alice")
        try state.mergeSuccessfulFetch([])
        XCTAssertEqual(state.entries.count, 2)
    }

    func testWrongRoomBatchIsRejectedAtomically() throws {
        var state = try RoomChatState(scope: scope)
        let other = RoomChatMessage(id: UUID(), roomCode: "OTHER", authorID: "bob",
                                    authorName: "Bob", text: "private", createdAt: Date(), moment: nil)
        XCTAssertThrowsError(try state.mergeSuccessfulFetch([other]))
        XCTAssertTrue(state.entries.isEmpty)
    }

    func testDraftAndInterruptedSendSurviveRestartWithAccountIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = RoomChatArchive(url: directory.appendingPathComponent("chat.json"))
        var state = try RoomChatState(scope: scope)
        state.draft = "send this"
        let message = try state.enqueue(authorName: "Alice")
        state.draft = "unfinished draft"
        try archive.save(state)
        let restored = try archive.load(scope: scope)
        XCTAssertEqual(restored.draft, state.draft)
        XCTAssertEqual(restored.entries.first?.id, message.id)
        XCTAssertEqual(restored.entries.first?.delivery, .failed)
        XCTAssertThrowsError(try archive.load(scope: .init(accountID: "bob", roomCode: scope.roomCode)))
        XCTAssertThrowsError(try archive.load(scope: .init(accountID: scope.accountID, roomCode: "OTHER")))
    }

    func testWhitespaceIsNotQueuedAndDuplicateSendIsRejected() throws {
        var state = try RoomChatState(scope: scope)
        state.draft = " \n "
        XCTAssertThrowsError(try state.enqueue(authorName: "Alice"))
        XCTAssertEqual(state.draft, " \n ")
        state.draft = "hello"
        let message = try state.enqueue(authorName: "Alice")
        XCTAssertThrowsError(try state.retry(message.id))
        XCTAssertEqual(state.entries.count, 1)
    }

    func testLegacyArchiveWithoutTombstonesStillDecodes() throws {
        var state = try RoomChatState(scope: scope)
        state.draft = "legacy draft"
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "deletedIDs")
        let decoded = try JSONDecoder().decode(RoomChatState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.draft, state.draft)
        XCTAssertTrue(decoded.deletedIDs.isEmpty)
    }

    func testMissingRecordNeverDeletesPendingSend() throws {
        var state = try RoomChatState(scope: scope)
        state.draft = "not uploaded"
        let message = try state.enqueue(authorName: "Alice")
        state.confirmDeleted([message.id])
        XCTAssertEqual(state.entries.count, 1)
        XCTAssertTrue(state.deletedIDs.isEmpty)
    }

    func testEqualTimestampsHaveStableOrdering() throws {
        var state = try RoomChatState(scope: scope)
        let date = Date(timeIntervalSince1970: 1)
        let ids = ["00000000-0000-0000-0000-000000000002", "00000000-0000-0000-0000-000000000001"]
        for id in ids {
            try state.acknowledge(.init(id: UUID(uuidString: id)!, roomCode: scope.roomCode,
                                       authorID: "bob", authorName: "Bob", text: "hello", createdAt: date, moment: nil))
        }
        XCTAssertEqual(state.orderedEntries.map { $0.id.uuidString }, ids.sorted())
    }
}
