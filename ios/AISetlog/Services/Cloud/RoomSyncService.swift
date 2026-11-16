import Foundation
import Observation

@Observable
final class RoomSyncService {
    var remoteClips: [String: [CloudKitService.RemoteClip]] = [:]
    var remoteReactions: [String: [CloudKitService.RemoteReaction]] = [:]
    var remoteComments: [String: [CloudKitService.RemoteComment]] = [:]
    var remoteMembers: [String: [String: CloudKitService.RemoteMember]] = [:]
    private(set) var syncing: Set<String> = []
    @ObservationIgnored private var uploading: Set<String> = []
    @ObservationIgnored private var roomGenerations: [String: UUID] = [:]
    private(set) var lastError: [String: String] = [:]

    private let fileStore: ClipFileStore
    private let transport: RoomSyncTransport
    private let cacheAccountID: () -> String?
    @ObservationIgnored private var loadedAccountID: String?

    init(fileStore: ClipFileStore = DiskClipFileStore(), transport: RoomSyncTransport = .live,
         cacheAccountID: @escaping () -> String? = { AccountStore.persistedUserID }) {
        self.fileStore = fileStore
        self.transport = transport
        self.cacheAccountID = cacheAccountID
        self.loadedAccountID = cacheAccountID()
    }

    func remoteCacheDir(for code: String) -> URL {
        fileStore.remoteCacheDir(roomCode: code)
    }

    func reconcileCacheAccount() {
        let current = cacheAccountID()
        guard current != loadedAccountID else { return }
        let codes = Set(remoteClips.keys).union(remoteReactions.keys).union(remoteComments.keys)
            .union(remoteMembers.keys).union(clipPulls.keys).union(memberPulls.keys)
        for code in codes { clearRoom(code) }
        loadedAccountID = current
    }

    func restoreCachedContent(code: String) {
        reconcileCacheAccount()
        restoreCachedMembers(code: code)
        let directory = remoteCacheDir(for: code)
        let accountID = cacheAccountID()
        if remoteClips[code] == nil, let cached = RoomContentCache.loadClips(in: directory, accountID: accountID) {
            remoteClips[code] = cached
        }
        if let saved = RoomContentCache.loadInteractions(in: directory, accountID: accountID) {
            if remoteReactions[code] == nil { remoteReactions[code] = saved.reactions }
            if remoteComments[code] == nil { remoteComments[code] = saved.comments }
        }
    }

    func clearRoom(_ code: String) {
        roomGenerations[code] = UUID()
        clipPulls[code]?.cancel()
        memberPulls[code]?.cancel()
        syncing.remove(code)
        let directory = remoteCacheDir(for: code)
        fileStore.deleteRemoteCache(roomCode: code)
        ClipThumbnailCache.shared.removeImages(in: directory)
        remoteClips[code] = nil
        remoteReactions[code] = nil
        remoteComments[code] = nil
        remoteMembers[code] = nil
        lastError[code] = nil
        forgetPublishedProfile(code: code)
        if pendingRoomTitles[code] != nil { setPendingRoomTitle(nil, code: code) }
    }

    @MainActor
    func syncClips(code: String) async -> [CloudKitService.RemoteClip]? {
        restoreCachedContent(code: code)
        let generation = roomGenerations[code]
        while let running = clipPulls[code] {
            _ = await running.value
            guard roomGenerations[code] == generation, !Task.isCancelled else { return nil }
        }
        guard !Task.isCancelled else { return nil }
        let pull = Task { @MainActor in
            let clips = await self.pullClips(code: code, generation: generation)
            self.clipPulls[code] = nil
            return clips
        }
        clipPulls[code] = pull
        return await pull.value
    }

    @ObservationIgnored private var clipPulls: [String: Task<[CloudKitService.RemoteClip]?, Never>] = [:]

    @MainActor
    private func pullClips(code: String, generation: UUID?) async -> [CloudKitService.RemoteClip]? {
        let accountID = cacheAccountID()
        let advertise = remoteClips[code] == nil || lastError[code] != nil
        if advertise { syncing.insert(code) }
        defer { if advertise { syncing.remove(code) } }
        do {
            var clips = try await transport.fetchClips(
                code, fileStore.remoteCacheDir(roomCode: code))
            #if DEBUG
            clips += await DebugFakeFriends.clips(for: code)
            #endif
            guard roomGenerations[code] == generation, cacheAccountID() == accountID,
                  !Task.isCancelled else { return nil }
            try? RoomContentCache.saveClips(clips, in: remoteCacheDir(for: code), accountID: accountID)
            if !Self.sameClips(remoteClips[code], clips) {
                remoteClips[code] = clips
            }
            if lastError[code] != nil { lastError[code] = nil }
            return clips
        } catch {
            guard roomGenerations[code] == generation, cacheAccountID() == accountID,
                  !Task.isCancelled else { return nil }
            print("[room] sync failed: \(error)")
            if lastError[code] != error.localizedDescription {
                lastError[code] = error.localizedDescription
            }
            #if DEBUG
            let fakes = await DebugFakeFriends.clips(for: code)
            if !fakes.isEmpty, !Self.sameClips(remoteClips[code], fakes) {
                remoteClips[code] = fakes
            }
            #endif
            return nil
        }
    }

    private static func sameClips(
        _ current: [CloudKitService.RemoteClip]?,
        _ incoming: [CloudKitService.RemoteClip]
    ) -> Bool {
        guard let current else { return false }
        return current.sorted { $0.id < $1.id } == incoming.sorted { $0.id < $1.id }
    }

    @MainActor
    func fetchInteractions(code: String) async -> (reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment])? {
        restoreCachedContent(code: code)
        let generation = roomGenerations[code]
        let accountID = cacheAccountID()
        let fetched = try? await transport.fetchInteractions(code)
        guard roomGenerations[code] == generation, cacheAccountID() == accountID,
              !Task.isCancelled else { return nil }
        guard let fetched else { return nil }
        let directory = remoteCacheDir(for: code)
        let saved = RoomContentCache.loadInteractions(in: directory, accountID: accountID) ?? .init()
        let merged = saved.refreshing(with: .init(reactions: fetched.reactions, comments: fetched.comments))
        try? RoomContentCache.saveInteractions(merged, in: directory, accountID: accountID)
        return (merged.reactions, merged.comments)
    }

    @MainActor
    func uploadClip(code: String, day: Int, authorID: String, authorName: String,
                    fileURL: URL, overlayText: String?, recordedAt: Date,
                    takeID: UUID? = nil) async -> Bool {
        await uploadClip(
            code: code, day: day, authorID: authorID, authorName: authorName,
            fileURL: fileURL, captions: .single(overlayText), recordedAt: recordedAt,
            takeID: takeID)
    }

    @MainActor
    func uploadClip(code: String, day: Int, authorID: String, authorName: String,
                    fileURL: URL, captions: [Caption], recordedAt: Date,
                    takeID: UUID? = nil) async -> Bool {
        let key = "\(code)#\(authorID)#\(day)#\(takeID?.uuidString ?? "1")"
        guard uploading.insert(key).inserted else { return false }
        defer { uploading.remove(key) }
        let generation = roomGenerations[code]
        do {
            try await transport.uploadClip(
                code, day, authorID, authorName, fileURL, captions, recordedAt, takeID)
            guard roomGenerations[code] == generation, !Task.isCancelled else { return false }
            lastError[code] = nil
            return true
        } catch {
            guard roomGenerations[code] == generation, !Task.isCancelled else { return false }
            print("[room] upload failed: \(error)")
            lastError[code] = error.localizedDescription
            return false
        }
    }

    @MainActor
    func updateClipCaption(
        code: String, day: Int, authorID: String, overlayText: String?, takeID: UUID? = nil
    ) async {
        await updateClipCaption(
            code: code, day: day, authorID: authorID, captions: .single(overlayText),
            takeID: takeID)
    }

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

    @MainActor
    func setReaction(code: String, day: Int, authorID: String, authorName: String,
                     targetAuthorID: String, emoji: String, on: Bool) async {
        reconcileCacheAccount()
        let generation = roomGenerations[code]
        let accountID = cacheAccountID()
        do {
            try await transport.setReaction(code, day, authorID, authorName, targetAuthorID, emoji, on)
            guard roomGenerations[code] == generation, cacheAccountID() == accountID, !Task.isCancelled else { return }
            updateCachedInteractions(code: code, change: .reaction(
                .init(day: day, emoji: emoji, authorID: authorID, authorName: authorName,
                      targetAuthorID: targetAuthorID, createdAt: .now), on: on))
        } catch { return }
    }

    @MainActor
    func postComment(code: String, day: Int, id: String, text: String,
                     authorID: String, authorName: String, targetAuthorID: String) async {
        reconcileCacheAccount()
        let generation = roomGenerations[code]
        let accountID = cacheAccountID()
        do {
            try await transport.postComment(code, day, id, text, authorID, authorName, targetAuthorID)
            guard roomGenerations[code] == generation, cacheAccountID() == accountID, !Task.isCancelled else { return }
            updateCachedInteractions(code: code, change: .comment(
                .init(id: id, day: day, text: text, authorID: authorID, authorName: authorName,
                      targetAuthorID: targetAuthorID, createdAt: .now)))
        } catch { return }
    }

    @MainActor
    func deleteComment(id: String, code: String) async {
        reconcileCacheAccount()
        let generation = roomGenerations[code]
        let accountID = cacheAccountID()
        do {
            try await transport.deleteComment(id)
            guard roomGenerations[code] == generation,
                  cacheAccountID() == accountID, !Task.isCancelled else { return }
            updateCachedInteractions(code: code, change: .deletedComment(id: id, at: .now))
        } catch { return }
    }

    private func updateCachedInteractions(code: String, change: RoomContentCache.ConfirmedChange) {
        let directory = remoteCacheDir(for: code)
        let accountID = cacheAccountID()
        var saved = RoomContentCache.loadInteractions(in: directory, accountID: accountID) ?? .init()
        saved.confirm(change)
        try? RoomContentCache.saveInteractions(saved, in: directory, accountID: accountID)
    }

    @MainActor
    func fetchRoom(code: String) async throws -> CloudKitService.RemoteRoom {
        try await transport.fetchRoom(code)
    }

    @MainActor
    func findMyRooms(userID: String) async -> CloudKitService.MyRooms? {
        do {
            return try await transport.findMyRooms(userID)
        } catch {
            print("[room] finding my rooms failed: \(error)")
            return nil
        }
    }

    @MainActor
    func recordMembership(code: String, authorID: String, displayName: String, joinedAt: Date = .now) async {
        do {
            try await transport.saveMember(code, authorID, displayName, joinedAt)
        } catch {
            print("[room] member record failed: \(error)")
        }
    }

    @MainActor
    func syncMembers(code: String) async {
        let generation = roomGenerations[code]
        while let running = memberPulls[code] {
            await running.value
            guard roomGenerations[code] == generation, !Task.isCancelled else { return }
        }
        guard !Task.isCancelled else { return }
        let pull = Task { @MainActor in
            await self.pullMembers(code: code, generation: generation)
            self.memberPulls[code] = nil
        }
        memberPulls[code] = pull
        await pull.value
    }

    @ObservationIgnored private var memberPulls: [String: Task<Void, Never>] = [:]

    @MainActor
    private func pullMembers(code: String, generation: UUID?) async {
        do {
            let members = try await transport.fetchMembers(code, membersDir(code))
            guard roomGenerations[code] == generation, !Task.isCancelled else { return }
            let next = Dictionary(members.map { ($0.userID, $0) }, uniquingKeysWith: { a, _ in a })
            if remoteMembers[code] != next {
                remoteMembers[code] = next
            }
            saveCachedMembers(members, code: code)
        } catch {
            guard roomGenerations[code] == generation, !Task.isCancelled else { return }
            print("[room] member fetch failed: \(error)")
        }
        #if DEBUG
        DebugMemberMoods.add(to: &remoteMembers, code: code, authors: (remoteClips[code] ?? []).map(\.authorID))
        #endif
    }

    private func membersDir(_ code: String) -> URL {
        fileStore.remoteCacheDir(roomCode: code).appendingPathComponent("members", isDirectory: true)
    }

    private func cachedMembersFile(_ code: String) -> URL {
        membersDir(code).appendingPathComponent("members.json")
    }

    private struct CachedMember: Codable {
        var userID: String
        var displayName: String
        var avatarFileName: String?
        var moodKind: String?
        var moodDay: Date?
        var roomTitle: String?
        var roomTitleAt: Date?
    }

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

    @MainActor
    func peopleInRoom(code: String, ownerID: String) async -> Set<String>? {
        guard let members = try? await transport.fetchMembers(
            code, fileStore.remoteCacheDir(roomCode: code).appendingPathComponent("members", isDirectory: true))
        else { return nil }
        var people = Set(members.map(\.userID))
        if !ownerID.isEmpty { people.insert(ownerID) }
        return people
    }

    @ObservationIgnored private var publishedProfiles: [String: String] =
        UserDefaults.standard.dictionary(forKey: RoomSyncService.publishedProfilesKey) as? [String: String] ?? [:]
    static let publishedProfilesKey = "memberProfile.published.v1"

    @MainActor
    @discardableResult
    func publishProfile(_ write: CloudKitService.MemberProfileWrite, signature: String) async -> Bool {
        guard publishedProfiles[write.code] != signature else { return false }
        let generation = roomGenerations[write.code]
        do {
            try await transport.saveMemberProfile(write)
            guard roomGenerations[write.code] == generation, !Task.isCancelled else { return false }
            publishedProfiles[write.code] = signature
            UserDefaults.standard.set(publishedProfiles, forKey: Self.publishedProfilesKey)
            return true
        } catch {
            print("[room] member profile failed: \(error)")
            return false
        }
    }

    func publishedProfileSignature(code: String) -> String? {
        publishedProfiles[code]
    }

    func forgetPublishedProfile(code: String) {
        guard publishedProfiles.removeValue(forKey: code) != nil else { return }
        UserDefaults.standard.set(publishedProfiles, forKey: Self.publishedProfilesKey)
    }


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


    struct PendingRoomTitle: Codable, Equatable {
        var title: String
        var at: Date
    }
    @ObservationIgnored private(set) var pendingRoomTitles: [String: PendingRoomTitle] = {
        guard let data = UserDefaults.standard.data(forKey: RoomSyncService.pendingRoomTitlesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: PendingRoomTitle].self, from: data)) ?? [:]
    }()
    static let pendingRoomTitlesKey = "roomTitle.pending.v1"

    @MainActor
    func publishRoomTitle(code: String, authorID: String, displayName: String, title: String? = nil, at: Date = .now) async {
        let generation = roomGenerations[code]
        if let title { setPendingRoomTitle(.init(title: title, at: at), code: code) }
        guard let pending = pendingRoomTitles[code] else { return }
        do {
            try await transport.saveRoomTitle(code, authorID, displayName, pending.title, pending.at)
            guard roomGenerations[code] == generation, !Task.isCancelled else { return }
            if pendingRoomTitles[code] == pending { setPendingRoomTitle(nil, code: code) }
        } catch {
            print("[room] room title failed: \(error)")
        }
    }

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

    @discardableResult
    func sendPoke(code: String, authorID: String, authorName: String, targetAuthorID: String) async -> Bool {
        do {
            try await transport.sendPoke(code, authorID, authorName, targetAuthorID)
            return true
        } catch {
            print("[room] poke failed: \(error)")
            return false
        }
    }

}
