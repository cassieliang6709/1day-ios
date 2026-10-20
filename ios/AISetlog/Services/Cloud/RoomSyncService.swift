import Foundation
import Observation

/// Owns CloudKit room sync for shared challenges: pulling members' clips and
/// interactions, pushing my clips/reactions/comments. The store keeps the
/// local mirror; this service is the only one that talks to CloudKitService.
@Observable
final class RoomSyncService {
    /// Clips fetched per room code (all members). Transient cache.
    ///
    /// Settable, like the two caches below it: the merge rules that read this
    /// live in `ChallengeStore`, and standing a room's contents up is the only
    /// way to check them without CloudKit on the line.
    var remoteClips: [String: [CloudKitService.RemoteClip]] = [:]
    /// Reactions fetched per room code.
    var remoteReactions: [String: [CloudKitService.RemoteReaction]] = [:]
    /// Comments fetched per room code.
    var remoteComments: [String: [CloudKitService.RemoteComment]] = [:]
    /// Everyone's `Member` record per room code, keyed by user ID: their
    /// avatar and today's mood. Settable for the same reason as the caches
    /// above.
    var remoteMembers: [String: [String: CloudKitService.RemoteMember]] = [:]
    /// Room codes currently being synced (drives a spinner in the board).
    private(set) var syncing: Set<String> = []
    /// Clips on their way up, as "code#authorID#day". Recording, the board's
    /// poll and coming back to the app can all reach `uploadClip` for the same
    /// take at once; one upload is enough.
    @ObservationIgnored private var uploading: Set<String> = []
    /// Last CloudKit failure per room. Kept visible instead of silently
    /// presenting an empty room when the production schema is unavailable.
    private(set) var lastError: [String: String] = [:]

    private let fileStore: ClipFileStore
    private let transport: RoomSyncTransport

    init(fileStore: ClipFileStore = DiskClipFileStore(), transport: RoomSyncTransport = .live) {
        self.fileStore = fileStore
        self.transport = transport
    }

    func remoteCacheDir(for code: String) -> URL {
        fileStore.remoteCacheDir(roomCode: code)
    }

    func clearRoom(_ code: String) {
        fileStore.deleteRemoteCache(roomCode: code)
        remoteClips[code] = nil
        remoteReactions[code] = nil
        remoteComments[code] = nil
        remoteMembers[code] = nil
        lastError[code] = nil
        forgetPublishedProfile(code: code)
    }

    /// Pull every member's clips for a room into the local cache. Interaction
    /// sync is handed back to the caller to merge into local state.
    @MainActor
    func syncClips(code: String) async -> [CloudKitService.RemoteClip]? {
        syncing.insert(code)
        defer { syncing.remove(code) }
        do {
            var clips = try await transport.fetchClips(
                code, fileStore.remoteCacheDir(roomCode: code))
            #if DEBUG
            clips += await DebugFakeFriends.clips(for: code)
            #endif
            remoteClips[code] = clips
            lastError[code] = nil
            return clips
        } catch {
            print("[room] sync failed: \(error)")
            lastError[code] = error.localizedDescription
            #if DEBUG
            let fakes = await DebugFakeFriends.clips(for: code)
            if !fakes.isEmpty { remoteClips[code] = fakes }
            #endif
            return nil
        }
    }

    /// Fetch remote reactions/comments. Degrades to nil (caller keeps local
    /// state) if the CloudKit index isn't deployed — never fails a clip sync.
    func fetchInteractions(code: String) async -> (reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment])? {
        try? await transport.fetchInteractions(code)
    }

    /// Push one of my clips to the room. The caller refreshes the complete room
    /// state after a successful upload so clips and interactions stay in sync.
    @MainActor
    func uploadClip(code: String, day: Int, authorID: String, authorName: String,
                    fileURL: URL, overlayText: String?, recordedAt: Date,
                    takeID: UUID? = nil) async -> Bool {
        await uploadClip(
            code: code, day: day, authorID: authorID, authorName: authorName,
            fileURL: fileURL, captions: .single(overlayText), recordedAt: recordedAt,
            takeID: takeID)
    }

    /// Same, with every caption on the take.
    @MainActor
    func uploadClip(code: String, day: Int, authorID: String, authorName: String,
                    fileURL: URL, captions: [Caption], recordedAt: Date,
                    takeID: UUID? = nil) async -> Bool {
        // A skipped duplicate reports false: it put nothing up itself, and a
        // take it shadowed is picked up by the next sync's retry. Keyed by take
        // as well as moment: two takes of one moment are two uploads.
        let key = "\(code)#\(authorID)#\(day)#\(takeID?.uuidString ?? "1")"
        guard uploading.insert(key).inserted else { return false }
        defer { uploading.remove(key) }
        do {
            try await transport.uploadClip(
                code, day, authorID, authorName, fileURL, captions, recordedAt, takeID)
            lastError[code] = nil
            return true
        } catch {
            print("[room] upload failed: \(error)")
            lastError[code] = error.localizedDescription
            return false
        }
    }

    /// Caption edited after the take. Failure is swallowed the same way a
    /// reaction's is: the words are already saved on this device, and the next
    /// upload of that clip carries them.
    @MainActor
    func updateClipCaption(
        code: String, day: Int, authorID: String, overlayText: String?, takeID: UUID? = nil
    ) async {
        await updateClipCaption(
            code: code, day: day, authorID: authorID, captions: .single(overlayText),
            takeID: takeID)
    }

    /// Same, with every caption on the take.
    @MainActor
    func updateClipCaption(
        code: String, day: Int, authorID: String, captions: [Caption], takeID: UUID? = nil
    ) async {
        do {
            try await transport.updateClipCaption(code, day, authorID, captions, takeID)
        } catch {
            print("[room] caption update failed: \(error)")
        }
    }

    func setReaction(code: String, day: Int, authorID: String, authorName: String,
                     targetAuthorID: String, emoji: String, on: Bool) async {
        try? await transport.setReaction(
            code, day, authorID, authorName, targetAuthorID, emoji, on)
    }

    func postComment(code: String, day: Int, id: String, text: String,
                     authorID: String, authorName: String, targetAuthorID: String) async {
        try? await transport.postComment(
            code, day, id, text, authorID, authorName, targetAuthorID)
    }

    func deleteComment(id: String) async {
        try? await transport.deleteComment(id)
    }

    /// The room behind a join code. Errors pass through untouched: they are
    /// what the join sheet shows.
    @MainActor
    func fetchRoom(code: String) async throws -> CloudKitService.RemoteRoom {
        try await transport.fetchRoom(code)
    }

    /// Leave a `Member` record saying I joined. Failure is logged and
    /// swallowed: the room is already mine on this device, and the record is
    /// bookkeeping, not what lets me in.
    @MainActor
    func recordMembership(code: String, authorID: String, displayName: String, joinedAt: Date = .now) async {
        do {
            try await transport.saveMember(code, authorID, displayName, joinedAt)
        } catch {
            print("[room] member record failed: \(error)")
        }
    }

    /// Pull the room's `Member` records — avatars and moods. Failure keeps
    /// what we had: before the `Member` type is deployed to Production every
    /// fetch fails, and that must not blank anybody's face.
    @MainActor
    func syncMembers(code: String) async {
        do {
            let members = try await transport.fetchMembers(
                code, fileStore.remoteCacheDir(roomCode: code).appendingPathComponent("members", isDirectory: true))
            remoteMembers[code] = Dictionary(members.map { ($0.userID, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            print("[room] member fetch failed: \(error)")
        }
        #if DEBUG
        DebugMemberMoods.add(to: &remoteMembers, code: code, authors: (remoteClips[code] ?? []).map(\.authorID))
        #endif
    }

    /// What was last written to my `Member` record per room, so the same
    /// avatar and mood aren't sent again on every foreground. Persisted:
    /// relaunching isn't a reason to upload the avatar to every room again.
    @ObservationIgnored private var publishedProfiles: [String: String] =
        UserDefaults.standard.dictionary(forKey: RoomSyncService.publishedProfilesKey) as? [String: String] ?? [:]
    static let publishedProfilesKey = "memberProfile.published.v1"

    /// Write my avatar and mood to one room's `Member` record, unless that
    /// exact `signature` already went up. A failure is logged and remembered as
    /// not sent, so the next call tries again; nothing waits on it.
    @MainActor
    @discardableResult
    func publishProfile(_ write: CloudKitService.MemberProfileWrite, signature: String) async -> Bool {
        guard publishedProfiles[write.code] != signature else { return false }
        do {
            try await transport.saveMemberProfile(write)
            publishedProfiles[write.code] = signature
            UserDefaults.standard.set(publishedProfiles, forKey: Self.publishedProfilesKey)
            return true
        } catch {
            print("[room] member profile failed: \(error)")
            return false
        }
    }

    /// What last went up for this room, if anything.
    func publishedProfileSignature(code: String) -> String? {
        publishedProfiles[code]
    }

    /// Joining rewrites the `Member` record from scratch; the next publish
    /// has to put the avatar and mood back.
    func forgetPublishedProfile(code: String) {
        guard publishedProfiles.removeValue(forKey: code) != nil else { return }
        UserDefaults.standard.set(publishedProfiles, forKey: Self.publishedProfilesKey)
    }

    func sendPoke(code: String, authorID: String, authorName: String, targetAuthorID: String) async {
        try? await transport.sendPoke(code, authorID, authorName, targetAuthorID)
    }

}
