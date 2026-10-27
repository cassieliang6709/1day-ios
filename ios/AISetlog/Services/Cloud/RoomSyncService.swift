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
        if pendingRoomTitles[code] != nil { setPendingRoomTitle(nil, code: code) }
    }

    /// Pull every member's clips for a room into the local cache. Interaction
    /// sync is handed back to the caller to merge into local state.
    ///
    /// Two pulls of the same room never overlap: the open room page polls while
    /// the foreground refresh may be syncing that room too, and both write the
    /// same cache directory and its manifest. A second caller waits for the
    /// running pull and then makes its own, so it never gets a result older
    /// than its call. Different rooms still run side by side.
    @MainActor
    func syncClips(code: String) async -> [CloudKitService.RemoteClip]? {
        while let running = clipPulls[code] {
            _ = await running.value
        }
        // The pull clears its own slot before it finishes, so a waiter woken
        // by it never finds the finished task still parked there. Nothing else
        // can have taken the slot meanwhile: it is only filled while empty.
        let pull = Task { @MainActor in
            let clips = await self.pullClips(code: code)
            self.clipPulls[code] = nil
            return clips
        }
        clipPulls[code] = pull
        return await pull.value
    }

    /// Room code → the clip pull running for it.
    @ObservationIgnored private var clipPulls: [String: Task<[CloudKitService.RemoteClip]?, Never>] = [:]

    @MainActor
    private func pullClips(code: String) async -> [CloudKitService.RemoteClip]? {
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

    /// The rooms I'm in according to the cloud, or nil when it can't say —
    /// signed out of iCloud, offline, or the indexes not deployed yet.
    @MainActor
    func findMyRooms(userID: String) async -> CloudKitService.MyRooms? {
        do {
            return try await transport.findMyRooms(userID)
        } catch {
            print("[room] finding my rooms failed: \(error)")
            return nil
        }
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
            let members = try await transport.fetchMembers(code, membersDir(code))
            remoteMembers[code] = Dictionary(members.map { ($0.userID, $0) }, uniquingKeysWith: { a, _ in a })
            saveCachedMembers(members, code: code)
        } catch {
            print("[room] member fetch failed: \(error)")
        }
        #if DEBUG
        DebugMemberMoods.add(to: &remoteMembers, code: code, authors: (remoteClips[code] ?? []).map(\.authorID))
        #endif
    }

    /// Where a room's avatars and its saved roster live. Inside the room's
    /// cache, so `clearRoom` and signing out take the roster with them.
    private func membersDir(_ code: String) -> URL {
        fileStore.remoteCacheDir(roomCode: code).appendingPathComponent("members", isDirectory: true)
    }

    private func cachedMembersFile(_ code: String) -> URL {
        membersDir(code).appendingPathComponent("members.json")
    }

    /// A `RemoteMember` as written to disk. The avatar is kept by file name:
    /// the app's container path changes across updates, so a saved absolute
    /// URL would point nowhere.
    private struct CachedMember: Codable {
        var userID: String
        var displayName: String
        var avatarFileName: String?
        var moodKind: String?
        var moodDay: Date?
        var roomTitle: String?
        var roomTitleAt: Date?
    }

    /// Puts last launch's roster back, so a cold start shows who is in the
    /// room before CloudKit answers. Does nothing once the room has one.
    @MainActor
    func restoreCachedMembers(code: String) {
        guard remoteMembers[code] == nil,
              let data = try? Data(contentsOf: cachedMembersFile(code)),
              let cached = try? JSONDecoder().decode([CachedMember].self, from: data)
        else { return }
        let dir = membersDir(code)
        let fm = FileManager.default
        let members = cached.map { c in
            let avatar = c.avatarFileName.map { dir.appendingPathComponent($0) }
            return CloudKitService.RemoteMember(
                userID: c.userID, displayName: c.displayName,
                avatarURL: avatar.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil },
                moodKind: c.moodKind, moodDay: c.moodDay,
                roomTitle: c.roomTitle, roomTitleAt: c.roomTitleAt)
        }
        remoteMembers[code] = Dictionary(members.map { ($0.userID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func saveCachedMembers(_ members: [CloudKitService.RemoteMember], code: String) {
        let cached = members.map {
            CachedMember(
                userID: $0.userID, displayName: $0.displayName,
                avatarFileName: $0.avatarURL?.lastPathComponent,
                moodKind: $0.moodKind, moodDay: $0.moodDay,
                roomTitle: $0.roomTitle, roomTitleAt: $0.roomTitleAt)
        }
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? FileManager.default.createDirectory(at: membersDir(code), withIntermediateDirectories: true)
        try? data.write(to: cachedMembersFile(code), options: .atomic)
    }

    /// Who is in a room by user ID — every `Member` record plus the owner,
    /// who may not have one. Nil when the records can't be read.
    @MainActor
    func peopleInRoom(code: String, ownerID: String) async -> Set<String>? {
        guard let members = try? await transport.fetchMembers(
            code, fileStore.remoteCacheDir(roomCode: code).appendingPathComponent("members", isDirectory: true))
        else { return nil }
        var people = Set(members.map(\.userID))
        if !ownerID.isEmpty { people.insert(ownerID) }
        return people
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

    // MARK: - Leaving

    /// Takes me out of a room for everyone (1.5): my clips, reactions,
    /// comments and `Member` record are deleted, so my frame and my footage
    /// leave every friend's copy. True when all of it is confirmed gone.
    @MainActor
    @discardableResult
    func leaveRemotely(code: String, authorID: String) async -> Bool {
        do {
            let names = try await transport.myRecordNames(code, authorID)
            let gone = try await transport.deleteRecords(names)
            print("[room] left code=\(code) deleted=\(gone.count)/\(names.count)")
            return gone.count == names.count
        } catch {
            print("[room] leave failed: \(error)")
            return false
        }
    }

    // MARK: - Room name

    /// A rename on this phone that hasn't reached my `Member` record yet,
    /// per room code. Persisted, and while it's here the room keeps my name
    /// rather than an older one fetched from someone else's record.
    struct PendingRoomTitle: Codable, Equatable {
        var title: String
        var at: Date
    }
    @ObservationIgnored private(set) var pendingRoomTitles: [String: PendingRoomTitle] = {
        guard let data = UserDefaults.standard.data(forKey: RoomSyncService.pendingRoomTitlesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: PendingRoomTitle].self, from: data)) ?? [:]
    }()
    static let pendingRoomTitlesKey = "roomTitle.pending.v1"

    /// Sends a new room name, or the one still waiting when `title` is nil.
    /// A failure (before the `Member` fields are deployed, every one) keeps it
    /// waiting for the next sync.
    @MainActor
    func publishRoomTitle(code: String, authorID: String, displayName: String, title: String? = nil, at: Date = .now) async {
        if let title { setPendingRoomTitle(.init(title: title, at: at), code: code) }
        guard let pending = pendingRoomTitles[code] else { return }
        do {
            try await transport.saveRoomTitle(code, authorID, displayName, pending.title, pending.at)
            if pendingRoomTitles[code] == pending { setPendingRoomTitle(nil, code: code) }
        } catch {
            print("[room] room title failed: \(error)")
        }
    }

    /// The room's name as its members last set it: the newest `roomTitle`
    /// across the room. Nil when nobody has renamed it, or while my own
    /// rename is still on its way up.
    func latestRoomTitle(code: String) -> String? {
        guard pendingRoomTitles[code] == nil else { return nil }
        return (remoteMembers[code] ?? [:]).values
            .compactMap { m in m.roomTitle.flatMap { t in m.roomTitleAt.map { (t, $0) } } }
            .max { $0.1 < $1.1 }?.0
    }

    private func setPendingRoomTitle(_ value: PendingRoomTitle?, code: String) {
        pendingRoomTitles[code] = value
        if let data = try? JSONEncoder().encode(pendingRoomTitles) {
            UserDefaults.standard.set(data, forKey: Self.pendingRoomTitlesKey)
        }
    }

    func sendPoke(code: String, authorID: String, authorName: String, targetAuthorID: String) async {
        try? await transport.sendPoke(code, authorID, authorName, targetAuthorID)
    }

}
