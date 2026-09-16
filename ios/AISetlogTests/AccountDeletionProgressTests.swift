import XCTest
@testable import AISetlog

final class AccountDeletionProgressTests: XCTestCase {
    func testLateWriteMustSettleBeforeDiscoveryAndBeIncludedInCleanup() throws {
        let token = UUID()
        var progress = try AccountDeletionProgress(accountID: "alice", inFlightWrites: [token])
        XCTAssertFalse(progress.allowsNewWrites)
        XCTAssertThrowsError(try progress.beginDiscovery())
        try progress.settleWrite(token, writtenRecordIDs: ["late-comment"])
        try progress.beginDiscovery()
        try progress.discovered(["old-comment"], isFinalPage: false)
        XCTAssertThrowsError(try progress.beginLocalCleanup())
        try progress.discovered(["clip", "late-comment"], isFinalPage: true)
        XCTAssertEqual(progress.pendingRecordIDs, ["late-comment", "old-comment", "clip"])
        XCTAssertThrowsError(try progress.beginLocalCleanup())
        try progress.confirmedDeleted(["old-comment", "clip"])
        progress.recordFailure(code: "networkUnavailable")
        XCTAssertEqual(progress.pendingRecordIDs, ["late-comment"])
        XCTAssertFalse(progress.allowsNewWrites)
        try progress.confirmedDeleted(["late-comment"])
        try progress.beginLocalCleanup()
        XCTAssertNotEqual(progress.phase, .completed)
        try progress.confirmLocalCleanup()
        XCTAssertEqual(progress.phase, .completed)
        XCTAssertFalse(progress.allowsNewWrites)
    }

    func testRestartRetainsPartialSuccessAndRetryDoesNotResetInventory() throws {
        var progress = try AccountDeletionProgress(accountID: "alice", inFlightWrites: [])
        try progress.beginDiscovery()
        try progress.discovered(["a", "b"], isFinalPage: true)
        try progress.confirmedDeleted(["a"])
        progress.recordFailure(code: "permissionDenied")
        var resumed = try JSONDecoder().decode(AccountDeletionProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(resumed, progress)
        try resumed.confirmedDeleted(["a"])
        XCTAssertEqual(resumed.pendingRecordIDs, ["b"])
        XCTAssertThrowsError(try resumed.confirmedDeleted(["not-in-inventory"]))
        try resumed.confirmedDeleted(["b"])
        try resumed.beginLocalCleanup()
        resumed.recordFailure(code: "diskFull")
        XCTAssertEqual(resumed.phase, .localCleanup)
        XCTAssertThrowsError(try resumed.beginDiscovery())
        try resumed.confirmLocalCleanup()
        XCTAssertEqual(resumed.phase, .completed)
    }

    func testUnknownCompletionAndInvalidPageCannotMutateState() throws {
        var progress = try AccountDeletionProgress(accountID: "alice", inFlightWrites: [])
        let original = progress
        XCTAssertThrowsError(try progress.settleWrite(UUID(), writtenRecordIDs: ["x"]))
        XCTAssertEqual(progress, original)
        try progress.beginDiscovery()
        let discovering = progress
        XCTAssertThrowsError(try progress.discovered(["good", ""], isFinalPage: true))
        XCTAssertEqual(progress, discovering)
        XCTAssertThrowsError(try progress.confirmLocalCleanup())
        XCTAssertFalse(progress.discoveryComplete)
    }

    func testEmptyInventoryStillRequiresExplicitLocalCleanupAcknowledgement() throws {
        var progress = try AccountDeletionProgress(accountID: "alice", inFlightWrites: [])
        try progress.beginDiscovery()
        try progress.discovered([], isFinalPage: true)
        try progress.beginLocalCleanup()
        XCTAssertEqual(progress.phase, .localCleanup)
        try progress.confirmLocalCleanup()
        XCTAssertEqual(progress.phase, .completed)
        XCTAssertThrowsError(try AccountDeletionProgress(accountID: "", inFlightWrites: []))
    }
}
