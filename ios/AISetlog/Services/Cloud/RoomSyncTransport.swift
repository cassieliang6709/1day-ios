import Foundation

/// The complete remote boundary of RoomSyncService. Supplying a transport never
/// falls back to CloudKit, including when an operation fails.
struct RoomSyncTransport {
    var fetchClips: @MainActor (String, URL) async throws -> [CloudKitService.RemoteClip]
    var fetchInteractions: @MainActor (String) async throws -> (reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment])
    var uploadClip: @MainActor (String, Int, String, String, URL, String?) async throws -> Void
    var setReaction: @MainActor (String, Int, String, String, String, String, Bool) async throws -> Void
    var postComment: @MainActor (String, Int, String, String, String, String, String) async throws -> Void
    var deleteComment: @MainActor (String) async throws -> Void

    static var live: RoomSyncTransport {
        RoomSyncTransport(
            fetchClips: { try await CloudKitService.fetchClips(code: $0, into: $1) },
            fetchInteractions: { try await CloudKitService.fetchInteractions(code: $0) },
            uploadClip: { try await CloudKitService.uploadClip(code: $0, day: $1, authorID: $2, authorName: $3, fileURL: $4, overlayText: $5) },
            setReaction: { try await CloudKitService.setReaction(code: $0, day: $1, authorID: $2, authorName: $3, targetAuthorID: $4, emoji: $5, on: $6) },
            postComment: { try await CloudKitService.postComment(code: $0, day: $1, id: $2, text: $3, authorID: $4, authorName: $5, targetAuthorID: $6) },
            deleteComment: { try await CloudKitService.deleteComment(id: $0) })
    }
}

#if DEBUG || LOCAL_ROOM_CHAT_DEMO
/// Read-only fixture source for the formal-room runtime under construction.
/// Unsupported writes fail closed; they must never claim an upload succeeded.
/// Local recording belongs to the isolated store, and room chat has its own transport.
@MainActor
final class LocalRoomSyncSource {
    enum Failure: Error { case closed, unknownRoom, readOnly }
    private let code: String
    private var clips: [CloudKitService.RemoteClip]
    private var closed = false

    init(code: String, clips: [CloudKitService.RemoteClip]) {
        self.code = code
        self.clips = clips
    }

    var transport: RoomSyncTransport {
        RoomSyncTransport(
            fetchClips: { [self] code, _ in
                try check(code)
                return clips
            },
            fetchInteractions: { [self] code in
                try check(code)
                return ([], [])
            },
            uploadClip: { [self] code, _, _, _, _, _ in try rejectWrite(code) },
            setReaction: { [self] code, _, _, _, _, _, _ in try rejectWrite(code) },
            postComment: { [self] code, _, _, _, _, _, _ in try rejectWrite(code) },
            deleteComment: { [self] _ in
                guard !closed else { throw Failure.closed }
                throw Failure.readOnly
            })
    }

    /// Local fixture administration only; remote transport writes remain rejected.
    func replaceClip(authorID: String, day: Int, url: URL) throws {
        try check(code)
        guard let index = clips.firstIndex(where: { $0.authorID == authorID && $0.day == day }) else {
            throw Failure.unknownRoom
        }
        let old = clips[index]
        clips[index] = .init(id: old.id, day: old.day, authorID: old.authorID,
            authorName: old.authorName, recordedAt: old.recordedAt,
            localURL: url, overlayText: old.overlayText)
    }

    func close() {
        closed = true
        clips = []
    }

    private func check(_ code: String) throws {
        guard !closed else { throw Failure.closed }
        guard code == self.code else { throw Failure.unknownRoom }
    }

    private func rejectWrite(_ code: String) throws {
        try check(code)
        throw Failure.readOnly
    }
}
#endif
