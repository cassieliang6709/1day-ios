import Foundation

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
