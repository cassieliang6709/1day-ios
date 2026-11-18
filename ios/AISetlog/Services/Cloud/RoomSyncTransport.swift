import Foundation

struct RoomSyncTransport {
    var fetchClips: @MainActor (String, URL) async throws -> [CloudKitService.RemoteClip]
    var fetchInteractions: @MainActor (String) async throws -> (reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment])
    var uploadClip: @MainActor (String, Int, String, String, URL, [Caption], Date, UUID?) async throws -> Void
    var updateClipCaption: @MainActor (String, Int, String, [Caption], UUID?) async throws -> Void
    var setReaction: @MainActor (String, Int, String, String, String, String, Bool) async throws -> Void
    var postComment: @MainActor (String, Int, String, String, String, String, String) async throws -> Void
    var deleteComment: @MainActor (String) async throws -> Void
    var sendPoke: @MainActor (String, String, String, String) async throws -> Void = { _, _, _, _ in
        throw CancellationError()
    }
    var fetchRoom: @MainActor (String) async throws -> CloudKitService.RemoteRoom = { _ in
        throw CancellationError()
    }
    var saveMember: @MainActor (String, String, String, Date) async throws -> Void = { _, _, _, _ in
        throw CancellationError()
    }
    var saveMemberProfile: @MainActor (CloudKitService.MemberProfileWrite) async throws -> Void = { _ in
        throw CancellationError()
    }
    var saveRoomTitle: @MainActor (String, String, String, String, Date) async throws -> Void = { _, _, _, _, _ in
        throw CancellationError()
    }
    var myRecordNames: @MainActor (String, String) async throws -> Set<String> = { _, _ in
        throw CancellationError()
    }
    var deleteRecords: @MainActor (Set<String>) async throws -> Set<String> = { _ in
        throw CancellationError()
    }
    var fetchMembers: @MainActor (String, URL) async throws -> [CloudKitService.RemoteMember] = { _, _ in
        throw CancellationError()
    }
    var findMyRooms: @MainActor (String) async throws -> CloudKitService.MyRooms = { _ in
        throw CancellationError()
    }

    static var live: RoomSyncTransport {
        RoomSyncTransport(
            fetchClips: { try await CloudKitService.fetchClips(code: $0, into: $1) },
            fetchInteractions: { try await CloudKitService.fetchInteractions(code: $0) },
            uploadClip: { try await CloudKitService.uploadClip(code: $0, day: $1, authorID: $2, authorName: $3, fileURL: $4, captions: $5, recordedAt: $6, takeID: $7) },
            updateClipCaption: { try await CloudKitService.updateClipCaption(code: $0, day: $1, authorID: $2, captions: $3, takeID: $4) },
            setReaction: { try await CloudKitService.setReaction(code: $0, day: $1, authorID: $2, authorName: $3, targetAuthorID: $4, emoji: $5, on: $6) },
            postComment: { try await CloudKitService.postComment(code: $0, day: $1, id: $2, text: $3, authorID: $4, authorName: $5, targetAuthorID: $6) },
            deleteComment: { try await CloudKitService.deleteComment(id: $0) },
            sendPoke: { try await CloudKitService.sendPoke(code: $0, authorID: $1, authorName: $2, targetAuthorID: $3) },
            fetchRoom: { try await CloudKitService.fetchRoom(code: $0) },
            saveMember: { try await CloudKitService.saveMember(code: $0, authorID: $1, displayName: $2, joinedAt: $3) },
            saveMemberProfile: { try await CloudKitService.saveMemberProfile($0) },
            saveRoomTitle: { try await CloudKitService.saveRoomTitle(code: $0, authorID: $1, displayName: $2, title: $3, at: $4) },
            myRecordNames: { try await CloudKitService.myRecordNames(inRoom: $0, authorID: $1) },
            deleteRecords: { try await CloudKitService.deleteRecordsConfirmingEachOne($0) },
            fetchMembers: { try await CloudKitService.fetchMembers(code: $0, into: $1) },
            findMyRooms: { try await CloudKitService.myRooms(userID: $0) })
    }
}

#if DEBUG || LOCAL_ROOM_CHAT_DEMO
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
            uploadClip: { [self] code, _, _, _, _, _, _, _ in try rejectWrite(code) },
            updateClipCaption: { [self] code, _, _, _, _ in try rejectWrite(code) },
            setReaction: { [self] code, _, _, _, _, _, _ in try rejectWrite(code) },
            postComment: { [self] code, _, _, _, _, _, _ in try rejectWrite(code) },
            deleteComment: { [self] _ in
                guard !closed else { throw Failure.closed }
                throw Failure.readOnly
            },
            sendPoke: { [self] code, _, _, _ in try rejectWrite(code) },
            fetchRoom: { [self] code in
                try check(code)
                throw Failure.readOnly
            },
            saveMember: { [self] code, _, _, _ in try rejectWrite(code) })
    }

    func replaceClip(authorID: String, day: Int, url: URL) throws {
        try check(code)
        guard let index = clips.firstIndex(where: { $0.authorID == authorID && $0.day == day }) else {
            throw Failure.unknownRoom
        }
        let old = clips[index]
        clips[index] = .init(id: old.id, day: old.day, authorID: old.authorID,
            authorName: old.authorName, recordedAt: old.recordedAt,
            localURL: url, overlayText: old.overlayText,
            captionSticker: old.captionSticker, captionsJSON: old.captionsJSON)
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
