import Foundation
import Observation

/// Owns CloudKit room sync for shared challenges: pulling members' clips and
/// interactions, pushing my clips/reactions/comments. The store keeps the
/// local mirror; this service is the only one that talks to CloudKitService.
@Observable
final class RoomSyncService {
    /// Clips fetched per room code (all members). Transient cache.
    private(set) var remoteClips: [String: [CloudKitService.RemoteClip]] = [:]
    /// Room codes currently being synced (drives a spinner in the board).
    private(set) var syncing: Set<String> = []

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
            return clips
        } catch {
            print("[room] sync failed: \(error)")
            return nil
        }
    }

    /// Fetch remote reactions/comments. Degrades to nil (caller keeps local
    /// state) if the CloudKit index isn't deployed — never fails a clip sync.
    func fetchInteractions(code: String) async -> (reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment])? {
        try? await CloudKitService.fetchInteractions(code: code)
    }

    /// Push one of my clips to the room (best-effort), then refresh the cache.
    @MainActor
    func uploadClip(code: String, day: Int, authorID: String, authorName: String,
                    fileURL: URL, overlayText: String?) async {
        do {
            try await CloudKitService.uploadClip(
                code: code, day: day, authorID: authorID,
                authorName: authorName, fileURL: fileURL,
                overlayText: overlayText)
            _ = await syncClips(code: code)
        } catch {
            print("[room] upload failed: \(error)")
        }
    }

    func setReaction(code: String, day: Int, authorID: String, authorName: String,
                     emoji: String, on: Bool) async {
        try? await CloudKitService.setReaction(
            code: code, day: day, authorID: authorID, authorName: authorName,
            emoji: emoji, on: on)
    }

    func postComment(code: String, day: Int, id: String, text: String,
                     authorID: String, authorName: String) async {
        try? await CloudKitService.postComment(
            code: code, day: day, id: id, text: text,
            authorID: authorID, authorName: authorName)
    }

    func deleteComment(id: String) async {
        try? await CloudKitService.deleteComment(id: id)
    }
}
