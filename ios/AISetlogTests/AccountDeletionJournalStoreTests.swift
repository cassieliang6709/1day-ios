import XCTest
@testable import AISetlog

@MainActor
final class AccountDeletionJournalStoreTests: XCTestCase {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("deletion-journal-test-\(UUID())/journal.json")
    }

    func testRealFileRestartResumesCursorInventoryAndDoesNotResetFreeze() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try AccountDeletionJournalStore(url: url, accountID: "mock")
        XCTAssertNil(try store.load())
        let token = UUID()
        let initial = try store.begin(inFlightWrites: [token])
        let coordinator = AccountDeletionCoordinator(journal: initial, dependencies: .init(
            save: store.save, discover: { _, _ in .init(recordIDs: ["first"], nextCursor: "page2") },
            delete: { _, _ in XCTFail(); return [] }, cleanLocal: { _ in XCTFail() }))
        try coordinator.settleWrite(token, recordIDs: ["late"])
        try await coordinator.advance()
        try await coordinator.advance()
        let reopened = try AccountDeletionJournalStore(url: url, accountID: "mock")
        let resumed = try reopened.begin(inFlightWrites: [])
        XCTAssertEqual(resumed, coordinator.journal)
        XCTAssertEqual(resumed.cursor, "page2")
        XCTAssertEqual(resumed.progress.pendingRecordIDs, ["first", "late"])
        XCTAssertFalse(resumed.progress.allowsNewWrites)
    }

    func testCorruptFutureAndWrongAccountNeverOverwriteEvidence() throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try AccountDeletionJournalStore(url: url, accountID: "mock")
        let journal = try store.begin(inFlightWrites: [])
        let original = try Data(contentsOf: url)
        let other = try AccountDeletionJournalStore(url: url, accountID: "other")
        XCTAssertThrowsError(try other.begin(inFlightWrites: []))
        XCTAssertEqual(try Data(contentsOf: url), original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        object["version"] = 999
        let future = try JSONSerialization.data(withJSONObject: object)
        for bytes in [future, Data("broken journal".utf8)] {
            try bytes.write(to: url, options: .atomic)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.begin(inFlightWrites: []))
            XCTAssertThrowsError(try store.save(journal))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    func testMissingAndInvalidStorageFailWithoutInventingProgress() throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try AccountDeletionJournalStore(url: url, accountID: "mock")
        let journal = AccountDeletionCoordinator.Journal(progress: try AccountDeletionProgress(accountID: "mock", inFlightWrites: []))
        XCTAssertThrowsError(try store.save(journal))
        XCTAssertNil(try store.load())
        XCTAssertThrowsError(try AccountDeletionJournalStore(url: url, accountID: "  "))
        try Data("not a directory".utf8).write(to: url.deletingLastPathComponent())
        XCTAssertThrowsError(try store.begin(inFlightWrites: []))
    }
}
