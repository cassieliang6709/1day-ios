import Foundation
import Observation

/// Owns CloudKit room sync for shared challenges: pulling members' clips and
/// interactions, pushing my clips/reactions/comments. The store keeps the
/// local mirror; this service is the only one that talks to CloudKitService.
@Observable
final class RoomSyncService {
    /// Clips fetched per room code (all members). Transient cache.
    private(set) var remoteClips: [String: [CloudKitService.RemoteClip]] = [:]
    /// Reactions fetched per room code.
    var remoteReactions: [String: [CloudKitService.RemoteReaction]] = [:]
    /// Comments fetched per room code.
    var remoteComments: [String: [CloudKitService.RemoteComment]] = [:]
    /// Room codes currently being synced (drives a spinner in the board).
    private(set) var syncing: Set<String> = []
    /// Last CloudKit failure per room. Kept visible instead of silently
    /// presenting an empty room when the production schema is unavailable.
    private(set) var lastError: [String: String] = [:]

    private let fileStore: ClipFileStore

    init(fileStore: ClipFileStore = DiskClipFileStore()) {
        self.fileStore = fileStore
    }

    func remoteCacheDir(for code: String) -> URL {
        fileStore.remoteCacheDir(roomCode: code)
    }

    func clearRoom(_ code: String) {
        fileStore.deleteRemoteCache(roomCode: code)
        remoteClips[code] = nil
        remoteReactions[code] = nil
        remoteComments[code] = nil
        lastError[code] = nil
    }

    /// Pull every member's clips for a room into the local cache. Interaction
    /// sync is handed back to the caller to merge into local state.
    @MainActor
    func syncClips(code: String) async -> [CloudKitService.RemoteClip]? {
        syncing.insert(code)
        defer { syncing.remove(code) }
        do {
            let clips = try await CloudKitService.fetchClips(
                code: code, into: fileStore.remoteCacheDir(roomCode: code))
            remoteClips[code] = clips
            lastError[code] = nil
            return clips
        } catch {
            print("[room] sync failed: \(error)")
            lastError[code] = error.localizedDescription
            return nil
        }
    }

    /// Fetch remote reactions/comments. Degrades to nil (caller keeps local
    /// state) if the CloudKit index isn't deployed — never fails a clip sync.
    func fetchInteractions(code: String) async -> (reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment])? {
        try? await CloudKitService.fetchInteractions(code: code)
    }

    /// Push one of my clips to the room. The caller refreshes the complete room
    /// state after a successful upload so clips and interactions stay in sync.
    @MainActor
    func uploadClip(code: String, day: Int, authorID: String, authorName: String,
                    fileURL: URL, overlayText: String?) async -> Bool {
        do {
            try await CloudKitService.uploadClip(
                code: code, day: day, authorID: authorID,
                authorName: authorName, fileURL: fileURL,
                overlayText: overlayText)
            lastError[code] = nil
            return true
        } catch {
            print("[room] upload failed: \(error)")
            lastError[code] = error.localizedDescription
            return false
        }
    }

    func setReaction(code: String, day: Int, authorID: String, authorName: String,
                     targetAuthorID: String, emoji: String, on: Bool) async {
        try? await CloudKitService.setReaction(
            code: code, day: day, authorID: authorID, authorName: authorName,
            targetAuthorID: targetAuthorID, emoji: emoji, on: on)
    }

    func postComment(code: String, day: Int, id: String, text: String,
                     authorID: String, authorName: String, targetAuthorID: String) async {
        try? await CloudKitService.postComment(
            code: code, day: day, id: id, text: text,
            authorID: authorID, authorName: authorName, targetAuthorID: targetAuthorID)
    }

    func deleteComment(id: String) async {
        try? await CloudKitService.deleteComment(id: id)
    }

#if DEBUG
    /// Put a room's contents in place without CloudKit. See `DemoRoom` — the
    /// only caller, and the only reason `remoteClips` isn't fully private.
    func stubRoom(
        code: String,
        clips: [CloudKitService.RemoteClip],
        reactions: [CloudKitService.RemoteReaction],
        comments: [CloudKitService.RemoteComment]
    ) {
        remoteClips[code] = clips
        remoteReactions[code] = reactions
        remoteComments[code] = comments
        lastError[code] = nil
    }
#endif
}
