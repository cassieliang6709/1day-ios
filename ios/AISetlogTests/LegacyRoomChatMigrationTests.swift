import XCTest
@testable import AISetlog

final class LegacyRoomChatMigrationTests: XCTestCase {
    private let scope = RoomChatScope(accountID: "alice", roomCode: "LOCAL")

    private func candidate(_ evidence: LegacyRoomChatMigration.Evidence,
                           id: UUID = UUID(), author: String = "alice", room: String = "LOCAL",
                           text: String = "  用户原文 English  ") -> LegacyRoomChatMigration.Candidate {
        .init(comment: ClipComment(id: id, text: text, authorID: author,
                                   authorName: "Alice", createdAt: Date(timeIntervalSince1970: 123)),
              roomCode: room, moment: 2, evidence: evidence)
    }

    func testOnlyProvenUnsentOwnCommentsRecoverWithoutChangingTextOrIdentity() throws {
        let own = candidate(.confirmedNeverUploaded)
        let unknown = candidate(.unknown)
        let other = candidate(.confirmedNeverUploaded, author: "bob")
        let state = try RoomChatState(scope: scope)
        let plan = LegacyRoomChatMigration.plan(candidates: [own, own, unknown, other], archive: state)
        XCTAssertEqual(plan.recoverable, [.init(message: own.message, delivery: .failed)])
        XCTAssertEqual(plan.unresolved, [unknown.message.id, other.message.id])
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(plan, LegacyRoomChatMigration.plan(candidates: [other, unknown, own, own], archive: state))
    }

    func testDeletionWinsOverUnsentAndOldRemoteSnapshot() throws {
        let own = candidate(.confirmedNeverUploaded)
        let deleted = candidate(.deleted, id: own.message.id)
        var state = try RoomChatState(scope: scope)
        try state.acknowledge(own.message)
        state.confirmDeleted([own.message.id])
        let plan = LegacyRoomChatMigration.plan(candidates: [own, deleted], archive: state)
        XCTAssertEqual(plan.tombstones, [own.message.id])
        XCTAssertTrue(plan.recoverable.isEmpty)
        XCTAssertTrue(plan.confirmedRemote.isEmpty)
    }

    func testConflictingDuplicateAndForeignRoomAreQuarantined() throws {
        let own = candidate(.confirmedNeverUploaded)
        let conflict = candidate(.confirmedNeverUploaded, id: own.message.id, text: "different")
        let foreign = candidate(.deleted, room: "OTHER")
        let plan = LegacyRoomChatMigration.plan(candidates: [own, conflict, foreign], archive: try RoomChatState(scope: scope))
        XCTAssertEqual(plan.unresolved, [own.message.id, foreign.message.id])
        XCTAssertTrue(plan.tombstones.isEmpty)
        XCTAssertTrue(plan.recoverable.isEmpty)
    }

    func testConfirmedRemoteIsIdempotentAfterArchiveAcknowledgement() throws {
        let own = candidate(.unknown)
        let confirmed = candidate(.remote(own.message), id: own.message.id)
        var state = try RoomChatState(scope: scope)
        let first = LegacyRoomChatMigration.plan(candidates: [confirmed], archive: state)
        XCTAssertEqual(first.confirmedRemote, [own.message])
        try state.mergeSuccessfulFetch(first.confirmedRemote)
        let second = LegacyRoomChatMigration.plan(candidates: [confirmed], archive: state)
        XCTAssertEqual(second, LegacyRoomChatMigration.Plan())
    }

    func testMismatchedRemoteAndInvalidTextNeverQueue() throws {
        let own = candidate(.unknown)
        let wrong = candidate(.remote(own.message))
        let blank = candidate(.confirmedNeverUploaded, text: " \n ")
        let long = candidate(.confirmedNeverUploaded, text: String(repeating: "a", count: 2001))
        let plan = LegacyRoomChatMigration.plan(candidates: [wrong, blank, long], archive: try RoomChatState(scope: scope))
        XCTAssertEqual(plan.unresolved, [wrong.message.id, blank.message.id, long.message.id])
        XCTAssertTrue(plan.recoverable.isEmpty)
        XCTAssertTrue(plan.confirmedRemote.isEmpty)
    }
}
