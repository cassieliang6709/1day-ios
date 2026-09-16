import Foundation

/// Non-destructive migration planning. No transport or disk access: callers must
/// persist the result before retiring legacy data. A missing query result is NOT
/// proof that a comment was never uploaded.
enum LegacyRoomChatMigration {
    enum Evidence: Equatable {
        case confirmedNeverUploaded
        case remote(RoomChatMessage)
        case deleted
        case unknown
    }

    struct Candidate: Equatable {
        let message: RoomChatMessage
        let evidence: Evidence

        init(comment: ClipComment, roomCode: String, moment: Int?, evidence: Evidence) {
            message = RoomChatMessage(id: comment.id, roomCode: roomCode,
                                      authorID: comment.authorID, authorName: comment.authorName,
                                      text: comment.text, createdAt: comment.createdAt, moment: moment)
            self.evidence = evidence
        }
    }

    struct Plan: Equatable {
        /// Explicitly unsent own comments only. Failed means manual retry, never auto-send.
        var recoverable: [RoomChatEntry] = []
        var confirmedRemote: [RoomChatMessage] = []
        /// Preserve these in legacy storage until provenance/conflicts are resolved.
        var unresolved: Set<UUID> = []
        var tombstones: Set<UUID> = []
    }

    static func plan(candidates: [Candidate], archive: RoomChatState) -> Plan {
        var result = Plan()
        let existing = Dictionary(archive.entries.map { ($0.id, $0.message) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: candidates, by: { $0.message.id })
        for id in grouped.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let group = grouped[id]!
            // Reject cross-room evidence before it can suppress an in-scope record.
            guard group.allSatisfy({ $0.message.roomCode == archive.scope.roomCode }) else {
                result.unresolved.insert(id)
                continue
            }
            if archive.deletedIDs.contains(id) || group.contains(where: { $0.evidence == .deleted }) {
                result.tombstones.insert(id)
                continue
            }
            let candidate = group[0]
            guard group.allSatisfy({ $0 == candidate }) else {
                result.unresolved.insert(id)
                continue
            }
            if let stored = existing[id] {
                if stored != candidate.message { result.unresolved.insert(id) }
                continue
            }
            switch candidate.evidence {
            case .confirmedNeverUploaded:
                let message = candidate.message
                guard message.authorID == archive.scope.accountID,
                      !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      message.text.count <= RoomChatState.maximumMessageLength else {
                    result.unresolved.insert(id)
                    continue
                }
                result.recoverable.append(RoomChatEntry(message: message, delivery: .failed))
            case .remote(let remote):
                // Stable ID alone does not authorize replacing another author's content.
                guard remote == candidate.message else {
                    result.unresolved.insert(id)
                    continue
                }
                result.confirmedRemote.append(remote)
            case .unknown:
                result.unresolved.insert(id)
            case .deleted:
                break
            }
        }
        return result
    }
}
