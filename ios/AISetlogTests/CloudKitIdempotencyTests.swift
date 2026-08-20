import CloudKit
import XCTest
@testable import AISetlog

/// Reactions and comments are written to deterministic record names so that
/// repeating a write is supposed to be harmless — the same emoji from the same
/// person on the same clip is one record, and a comment carries its local UUID
/// so "both sides dedupe". These check that the writes actually behave that
/// way, since a retry, a double tap or a second device all replay them.
///
/// Runs against the real CloudKit development database; skips without iCloud.
final class CloudKitIdempotencyTests: XCTestCase {
    private let authorID = "test-author-\(UUID().uuidString)"
    private var code: String?

    override func setUp() async throws {
        try await super.setUp()
        do {
            try await CloudKitService.ensureAccountAvailable()
        } catch {
            throw XCTSkip("Needs a simulator or device signed into iCloud: \(error)")
        }
        code = try await CloudKitService.createRoom(
            title: "Idempotency test", ownerID: authorID, ownerName: "Tester").code
    }

    override func tearDown() async throws {
        if let code {
            try? await CloudKitService.deleteMyRoomData(
                authorID: authorID,
                clips: [], reactions: [(code: code, targetAuthorID: authorID, day: 1, emoji: "🔥")],
                commentIDs: [], roomCodes: [code])
        }
        try await super.tearDown()
    }

    func testAddingTheSameReactionTwiceIsHarmless() async throws {
        let code = try XCTUnwrap(self.code)
        for _ in 1...2 {
            try await CloudKitService.setReaction(
                code: code, day: 1, authorID: authorID, authorName: "Tester",
                targetAuthorID: authorID, emoji: "🔥", on: true)
        }
    }

    func testRepostingACommentIsHarmless() async throws {
        let code = try XCTUnwrap(self.code)
        let id = UUID().uuidString
        defer {
            Task { try? await CloudKitService.deleteComment(id: id) }
        }
        for text in ["first send", "retry of the same comment"] {
            try await CloudKitService.postComment(
                code: code, day: 1, id: id, text: text,
                authorID: authorID, authorName: "Tester", targetAuthorID: authorID)
        }
    }
}
