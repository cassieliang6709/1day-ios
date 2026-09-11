import Foundation

/// Synchronous transaction for an exclusively owned chat archive. Integration
/// must run on the session's actor, before publishing the returned state; do not
/// run a second writer against the same file. Legacy sources are never retired
/// here, including on success: unresolved provenance still needs review.
enum LegacyRoomChatRecovery {
    struct Result {
        let state: RoomChatState
        let plan: LegacyRoomChatMigration.Plan
    }

    static func recover(candidates: [LegacyRoomChatMigration.Candidate],
                        scope: RoomChatScope, archive: RoomChatArchive) throws -> Result {
        try recover(candidates: candidates, scope: scope,
                    load: { try archive.load(scope: scope) }, save: archive.save)
    }

    /// Injection supports deterministic disk failures without touching real data.
    /// No result is published until atomic archive persistence succeeds.
    static func recover(candidates: [LegacyRoomChatMigration.Candidate], scope: RoomChatScope,
                        load: () throws -> RoomChatState,
                        save: (RoomChatState) throws -> Void) throws -> Result {
        var next = try load()
        guard next.scope == scope else { throw RoomChatArchive.ArchiveError.scopeMismatch }
        let plan = next.recoverLegacyComments(candidates)
        try save(next)
        return Result(state: next, plan: plan)
    }
}
