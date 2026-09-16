import XCTest
@testable import AISetlog

final class LegacyRoomChatRecoveryTests: XCTestCase {
    private let scope = RoomChatScope(accountID: "alice", roomCode: "LOCAL")

    private func candidate(_ evidence: LegacyRoomChatMigration.Evidence, id: UUID = UUID()) -> LegacyRoomChatMigration.Candidate {
        .init(comment: ClipComment(id: id, text: "  原文 English\n", authorID: "alice",
                                   authorName: "Alice", createdAt: Date(timeIntervalSince1970: 123)),
              roomCode: "LOCAL", moment: 2, evidence: evidence)
    }

    func testAtomicArchiveRoundTripIsIdempotentAndPreservesDraftAndOriginalText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = RoomChatArchive(url: directory.appendingPathComponent("chat.json"))
        var original = try RoomChatState(scope: scope)
        original.draft = "unfinished draft"
        try archive.save(original)
        let unsent = candidate(.confirmedNeverUploaded)
        let unknown = candidate(.unknown)
        let remote = candidate(.unknown)
        let confirmed = candidate(.remote(remote.message), id: remote.message.id)
        let candidates = [unsent, unknown, confirmed]
        let result = try LegacyRoomChatRecovery.recover(candidates: candidates, scope: scope, archive: archive)
        XCTAssertEqual(result.state.draft, original.draft)
        XCTAssertEqual(result.state.entries.first { $0.id == unsent.message.id }, .init(message: unsent.message, delivery: .failed))
        XCTAssertEqual(result.state.entries.first { $0.id == remote.message.id }?.delivery, .sent)
        XCTAssertEqual(result.plan.unresolved, [unknown.message.id])
        XCTAssertEqual(try archive.load(scope: scope), result.state)
        let again = try LegacyRoomChatRecovery.recover(candidates: candidates, scope: scope, archive: archive)
        XCTAssertEqual(again.state, result.state)
        XCTAssertTrue(again.plan.recoverable.isEmpty)
        XCTAssertTrue(again.plan.confirmedRemote.isEmpty)
        XCTAssertEqual(again.plan.unresolved, [unknown.message.id])
    }

    func testDeletionPersistsForAbsentAndFailedEntriesAndBlocksOldSnapshots() throws {
        let absent = candidate(.deleted)
        let unsent = candidate(.confirmedNeverUploaded)
        var state = try RoomChatState(scope: scope)
        state.recoverLegacyComments([unsent])
        state.recoverLegacyComments([absent, candidate(.deleted, id: unsent.message.id)])
        state = try JSONDecoder().decode(RoomChatState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(state.deletedIDs, [absent.message.id, unsent.message.id])
        try state.mergeSuccessfulFetch([absent.message, unsent.message])
        state.recoverLegacyComments([unsent])
        XCTAssertTrue(state.entries.isEmpty)
    }

    func testFailedSaveDoesNotPublishOrMutateExistingStateAndRetryRecovers() throws {
        enum DiskFailure: Error { case full }
        var persisted = try RoomChatState(scope: scope)
        persisted.draft = "keep me"
        let original = persisted
        let unsent = candidate(.confirmedNeverUploaded)
        XCTAssertThrowsError(try LegacyRoomChatRecovery.recover(candidates: [unsent], scope: scope,
                                                               load: { persisted }, save: { _ in throw DiskFailure.full }))
        XCTAssertEqual(persisted, original)
        let recovered = try LegacyRoomChatRecovery.recover(candidates: [unsent], scope: scope,
                                                           load: { persisted }, save: { persisted = $0 })
        XCTAssertEqual(persisted, recovered.state)
        XCTAssertEqual(persisted.entries.count, 1)
    }

    func testWrongScopeAndCorruptArchiveNeverInvokeSaveOrOverwriteBytes() throws {
        let other = try RoomChatState(scope: .init(accountID: "bob", roomCode: "LOCAL"))
        var saves = 0
        XCTAssertThrowsError(try LegacyRoomChatRecovery.recover(candidates: [], scope: scope,
                                                               load: { other }, save: { _ in saves += 1 }))
        XCTAssertEqual(saves, 0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = RoomChatArchive(url: directory.appendingPathComponent("chat.json"))
        let corrupt = Data("not an archive".utf8)
        try corrupt.write(to: archive.url)
        XCTAssertThrowsError(try LegacyRoomChatRecovery.recover(candidates: [], scope: scope, archive: archive))
        XCTAssertEqual(try Data(contentsOf: archive.url), corrupt)
    }

    func testCurrentArchiveConflictIsNotOverwrittenByLegacyEvidence() throws {
        let old = candidate(.confirmedNeverUploaded)
        var current = try RoomChatState(scope: scope)
        current.draft = "new content"
        let newer = try current.enqueue(authorName: "Alice", id: old.message.id)
        let plan = current.recoverLegacyComments([old])
        XCTAssertEqual(plan.unresolved, [old.message.id])
        XCTAssertEqual(current.entries, [.init(message: newer, delivery: .sending)])
    }
}
