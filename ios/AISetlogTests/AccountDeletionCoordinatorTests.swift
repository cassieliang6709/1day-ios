import XCTest
@testable import AISetlog

@MainActor
final class AccountDeletionCoordinatorTests: XCTestCase {
    enum StubError: Error { case disk, network }

    func testPaginationPartialDeletionAndRestartCommitCursorWithInventory() async throws {
        var durable = AccountDeletionCoordinator.Journal(
            progress: try AccountDeletionProgress(accountID: "mock-account", inFlightWrites: []))
        var cursors: [String?] = []
        var batches: [Set<String>] = []
        var cleaned = 0
        let dependencies = AccountDeletionCoordinator.Dependencies(save: { durable = $0 }, discover: { account, cursor in
            XCTAssertEqual(account, "mock-account")
            cursors.append(cursor)
            return .init(recordIDs: cursor == nil ? ["a"] : ["b"], nextCursor: cursor == nil ? "page2" : nil)
        }, delete: { _, ids in
            batches.append(ids)
            return batches.count == 1 ? ["a"] : ids
        }, cleanLocal: { _ in cleaned += 1 })
        let first = AccountDeletionCoordinator(journal: durable, dependencies: dependencies)
        try await first.advance()
        try await first.advance()
        let encoded = try JSONEncoder().encode(durable)
        let restored = try JSONDecoder().decode(AccountDeletionCoordinator.Journal.self, from: encoded)
        let resumed = AccountDeletionCoordinator(journal: restored, dependencies: dependencies)
        try await resumed.advance()
        try await resumed.advance()
        XCTAssertEqual(resumed.journal.progress.pendingRecordIDs, ["b"])
        XCTAssertEqual(cleaned, 0)
        try await resumed.advance()
        try await resumed.advance()
        try await resumed.advance()
        try await resumed.advance() // completed is a no-op
        XCTAssertEqual(cursors, [nil, "page2"])
        XCTAssertEqual(batches, [["a", "b"], ["b"]])
        XCTAssertEqual(cleaned, 1)
        XCTAssertEqual(durable.progress.phase, .completed)
        XCTAssertFalse(durable.progress.allowsNewWrites)
    }

    func testSaveFailureReplaysConfirmedRemoteDeleteWithoutFalseCompletion() async throws {
        var progress = try AccountDeletionProgress(accountID: "mock", inFlightWrites: [])
        try progress.beginDiscovery()
        try progress.discovered(["a"], isFinalPage: true)
        let initial = AccountDeletionCoordinator.Journal(progress: progress)
        var failSave = true
        var deleted = 0
        let coordinator = AccountDeletionCoordinator(journal: initial, dependencies: .init(save: { _ in
            if failSave { throw StubError.disk }
        }, discover: { _, _ in XCTFail(); throw StubError.network }, delete: { _, ids in
            deleted += 1
            return ids
        }, cleanLocal: { _ in XCTFail() }))
        do { try await coordinator.advance(); XCTFail() } catch {}
        XCTAssertEqual(coordinator.journal, initial)
        XCTAssertFalse(coordinator.isRunning)
        failSave = false
        try await coordinator.advance()
        XCTAssertEqual(deleted, 2)
        XCTAssertTrue(coordinator.journal.progress.pendingRecordIDs.isEmpty)
        XCTAssertEqual(coordinator.journal.progress.phase, .deleting)
    }

    func testInFlightWriteMustSettleAndDiscoveryFailurePreservesLateRecord() async throws {
        let token = UUID()
        let initial = AccountDeletionCoordinator.Journal(progress: try AccountDeletionProgress(accountID: "mock", inFlightWrites: [token]))
        var fetches = 0
        let coordinator = AccountDeletionCoordinator(journal: initial, dependencies: .init(save: { _ in }, discover: { _, _ in
            fetches += 1
            throw StubError.network
        }, delete: { _, _ in XCTFail(); return [] }, cleanLocal: { _ in XCTFail() }))
        do { try await coordinator.advance(); XCTFail() } catch {}
        XCTAssertEqual(fetches, 0)
        try coordinator.settleWrite(token, recordIDs: ["late"])
        try await coordinator.advance()
        do { try await coordinator.advance(); XCTFail() } catch {}
        XCTAssertEqual(coordinator.journal.progress.phase, .discovering)
        XCTAssertEqual(coordinator.journal.progress.pendingRecordIDs, ["late"])
        XCTAssertFalse(coordinator.journal.progress.allowsNewWrites)
    }

    func testConcurrentAdvanceRejectedAndCleanupFailureNeverCompletes() async throws {
        var progress = try AccountDeletionProgress(accountID: "mock", inFlightWrites: [])
        try progress.beginDiscovery()
        try progress.discovered([], isFinalPage: true)
        try progress.beginLocalCleanup()
        var continuation: CheckedContinuation<Void, Error>?
        let coordinator = AccountDeletionCoordinator(journal: .init(progress: progress), dependencies: .init(save: { _ in }, discover: { _, _ in XCTFail(); throw StubError.network }, delete: { _, _ in XCTFail(); return [] }, cleanLocal: { _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }))
        let task = Task { try await coordinator.advance() }
        while continuation == nil { await Task.yield() }
        do { try await coordinator.advance(); XCTFail() } catch AccountDeletionCoordinator.Failure.busy {} catch { XCTFail("Unexpected error") }
        continuation?.resume(throwing: StubError.network)
        do { try await task.value; XCTFail() } catch {}
        XCTAssertEqual(coordinator.journal.progress.phase, .localCleanup)
        XCTAssertFalse(coordinator.isRunning)
    }
}
