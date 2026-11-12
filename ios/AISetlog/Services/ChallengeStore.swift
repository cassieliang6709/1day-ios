import Foundation
import Observation

/// Holds challenge state in memory and orchestrates the services around it:
/// persistence (ChallengeRepository), clip files (ClipFileStore), and room
/// sync (RoomSyncService). Contains no I/O of its own beyond delegating.
@Observable
final class ChallengeStore {
    var challenges: [Challenge] = [] {
        didSet {
            repository.saveChallenges(challenges)
            effects.reconcileReminders(challenges)
            let oldRooms = Set(oldValue.compactMap(\.roomCode))
            let newRooms = Set(challenges.compactMap(\.roomCode))
            if oldRooms != newRooms {
                effects.reconcileSubscriptions(challenges)
            }
        }
    }

    /// Set once at app launch so shared rooms can attribute + upload clips.
    var account: AccountStore?
    /// My avatar and today's mood, as rooms should show them. Set at launch;
    /// read whenever a room needs my `Member` record brought up to date.
    var myRoomProfile: @MainActor () -> MyRoomProfile? = { nil }
    /// This phone's own avatar: put one back from the cloud, or wipe it when
    /// someone else signs in. Set at launch; no-ops in tests and previews.
    var adoptAvatar: @MainActor (URL) -> Void = { _ in }
    var forgetAvatar: @MainActor () -> Void = {}

    /// CloudKit room sync (remote clip cache + syncing spinners live there).
    let roomSync: RoomSyncService
    /// A newer interaction refresh wins even if an older request returns last.
    @ObservationIgnored private var interactionRequests: [UUID: UUID] = [:]

    private let repository: ChallengeRepository
    private let fileStore: ClipFileStore
    let effects: ChallengeStoreEffects

    init(repository: ChallengeRepository? = nil,
         fileStore: ClipFileStore = DiskClipFileStore(),
         roomSync: RoomSyncService? = nil,
         effects: ChallengeStoreEffects = .live) {
        self.effects = effects
        self.fileStore = fileStore
        self.repository = repository ?? UserDefaultsChallengeRepository(fileStore: fileStore)
        self.roomSync = roomSync ?? RoomSyncService(fileStore: fileStore)
        challenges = self.repository.loadChallenges()
    }

    /// Room codes currently being synced (drives a spinner in the board).
    var syncing: Set<String> { roomSync.syncing }

    func syncError(for challengeID: UUID) -> String? {
        guard let code = challenge(challengeID)?.roomCode else { return nil }
        return roomSync.lastError[code]
    }

    func challenge(_ id: UUID) -> Challenge? {
        challenges.first { $0.id == id }
    }

    func updatePlan(_ id: UUID, title: String, momentTitles: [String]) {
        guard let index = challenges.firstIndex(where: { $0.id == id }) else { return }
        var updated = challenges[index]
        updated.title = title
        updated.momentTitles = momentTitles
        challenges[index] = updated
    }

    /// 编辑计划 (1.5): the list rewritten — reordered, added to, trimmed. Each
    /// item names the slot it came from, so its footage moves with it; a new
    /// item gets an empty slot. A slot left out loses its card, which is why
    /// the editor never lets an item with footage be removed.
    func replacePlan(_ id: UUID, items: [(title: String, fromSlot: Int?)]) {
        guard let index = challenges.firstIndex(where: { $0.id == id }), !items.isEmpty else { return }
        var updated = challenges[index]
        let old = Dictionary(updated.cards.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        updated.cards = items.enumerated().map { offset, item in
            var card = item.fromSlot.flatMap { old[$0] } ?? DayCard(day: offset + 1)
            card.day = offset + 1
            return card
        }
        updated.momentTitles = items.map(\.title)
        challenges[index] = updated
    }

    @discardableResult
    func create(
        title: String,
        mode: Challenge.Mode = .sevenDay,
        clipLength: Challenge.ClipLength = .tiny,
        orientation: Challenge.Orientation = .portrait,
        cameraStyle: CameraStyle? = nil,
        templateName: String? = nil,
        momentTitles: [String]? = nil,
        startDate: Date = .now
    ) -> Challenge {
        let challenge = Challenge(
            id: UUID(),
            title: title,
            startDate: startDate,
            cards: (1...cardCount(for: momentTitles)).map { DayCard(day: $0) },
            mode: mode,
            clipLength: clipLength,
            orientation: orientation,
            cameraStyle: cameraStyle,
            templateName: templateName,
            momentTitles: momentTitles
        )
        challenges.insert(challenge, at: 0)
        return challenge
    }

    /// The first-run story: an immediately filmable personal day. Keeping this
    /// alongside `create` means it has the exact same persistence and reminder
    /// behavior as a story made in the composer.
    ///
    /// 按时间 as of 1.5 — no prompts to read before the first take, which is
    /// what 晨光 / 在路上 / 傍晚的光 asked of someone who had just opened the app.
    @discardableResult
    func createQuickStart() -> Challenge {
        create(
            title: Strings.quickStartTitle,
            mode: .oneDay,
            clipLength: .tiny,
            orientation: .portrait,
            templateName: Challenge.timeOnlyTemplateName,
            momentTitles: nil)
    }

    // MARK: - Shared rooms (CloudKit)

    enum RoomError: LocalizedError {
        case notSignedIn
        var errorDescription: String? { Strings.errorSignInFirst }
    }

    /// A preview cannot manage real rooms or erase a real account.
    enum IsolationError: Error { case cloudRoomManagementDisabled }

    /// Create a CloudKit-backed room and mirror it locally.
    @MainActor
    @discardableResult
    func createSharedRoom(
        title: String,
        mode: Challenge.Mode = .sevenDay,
        clipLength: Challenge.ClipLength = .tiny,
        orientation: Challenge.Orientation = .portrait,
        cameraStyle: CameraStyle? = nil,
        templateName: String? = nil,
        momentTitles: [String]? = nil
    ) async throws -> Challenge {
        guard effects.allowsCloudRoomManagement else { throw IsolationError.cloudRoomManagementDisabled }
        guard let me = account?.account else { throw RoomError.notSignedIn }
        let room = try await CloudKitService.createRoom(
            title: title, ownerID: me.id, ownerName: me.displayName,
            mode: mode, clipLength: clipLength, orientation: orientation,
            cameraStyle: cameraStyle,
            templateName: templateName, momentTitles: momentTitles)
        let challenge = Challenge(
            id: UUID(), title: room.title, startDate: room.startDate,
            cards: (1...cardCount(for: room.momentTitles)).map { DayCard(day: $0) },
            mode: room.mode, clipLength: room.clipLength,
            orientation: room.orientation,
            cameraStyle: room.cameraStyle,
            templateName: room.templateName,
            momentTitles: room.momentTitles,
            roomCode: room.code, ownerName: room.ownerName, ownerID: room.ownerID)
        challenges.insert(challenge, at: 0)
        // My `Member` record, as joining writes one: it is how this room
        // finds its way back to me on another phone (`restoreMyRooms`).
        await roomSync.recordMembership(
            code: room.code, authorID: me.id, displayName: me.displayName)
        await publishMyProfile(toRoom: room.code)
        return challenge
    }

    /// Rooms made before every owner got a `Member` record (1.5 (36)). Only
    /// these come back through `Room.ownerID`: a later room I made and then
    /// left has no `Member` record either, and must stay left.
    static let ownerMemberRecordsSince = DateComponents(
        calendar: .init(identifier: .gregorian), timeZone: .init(identifier: "Asia/Shanghai"),
        year: 2026, month: 10, day: 28).date!

    @ObservationIgnored private var roomRestoration: (userID: String, revision: UInt64, request: UUID)?

    /// Whose the shared rooms on this phone are. Signing out keeps them (and
    /// any take whose upload hasn't landed yet) for the same person coming
    /// back; it can't keep them for someone else.
    static let roomsAccountKey = "rooms.accountID.v1"

    /// Run on sign-in and on every foreground. Someone other than the last
    /// person signed in here: their shared rooms, takes and avatar leave this
    /// phone first — left in place, the next sync uploaded every one of their
    /// takes under the new account and joined it to their rooms. Only this
    /// phone's copy goes; the rooms and takes stay in the cloud, and come back
    /// when that person signs in again (`restoreMyRooms`). Personal stories
    /// stay: they never leave the phone. Then the new person's rooms come back.
    @MainActor
    func reconcileAccountRooms(defaults: UserDefaults = .standard) async {
        guard let me = account?.account else { return }
        if let previous = defaults.string(forKey: Self.roomsAccountKey), previous != me.id {
            for challenge in challenges where challenge.isShared {
                fileStore.deleteClips(challengeID: challenge.id)
                if let code = challenge.roomCode { roomSync.clearRoom(code) }
            }
            challenges.removeAll(where: \.isShared)
            forgetAvatar()
            print("[room] another account signed in; this phone's copy of the old rooms is gone")
        }
        defaults.set(me.id, forKey: Self.roomsAccountKey)
        await restoreMyRooms()
    }

    /// Puts back every room the cloud says I'm in that this phone doesn't
    /// have — a new phone, a reinstall, or the Dev build next to the App
    /// Store one. The room list lives on the phone; the cloud only knows it
    /// through my `Member` records and the rooms I own. Rooms I left have
    /// neither, so they stay gone. Nothing is removed here: a room the
    /// cloud can't vouch for may just be one the query missed.
    @MainActor
    func restoreMyRooms() async {
        guard effects.allowsCloudRoomManagement, let me = account?.account
        else { return }
        let revision = AccountStore.identityRevision
        guard roomRestoration?.userID != me.id || roomRestoration?.revision != revision else { return }
        let request = UUID()
        roomRestoration = (me.id, revision, request)
        defer {
            if roomRestoration?.request == request { roomRestoration = nil }
        }
        guard let mine = await roomSync.findMyRooms(userID: me.id) else { return }
        guard isCurrentAccount(me.id, revision: revision), roomRestoration?.request == request,
              !Task.isCancelled else { return }
        // Apple hands the name over only on the very first sign-in, and the
        // avatar lives in a file on the old phone: a new phone has neither.
        // My own `Member` records still do.
        if me.name == nil, let name = mine.displayName { account?.rename(to: name) }
        if myRoomProfile()?.avatarURL == nil, let avatar = mine.avatarFile { adoptAvatar(avatar) }

        let have = Set(challenges.compactMap(\.roomCode))
        var rooms: [CloudKitService.RemoteRoom] = mine.owned.filter {
            !have.contains($0.code)
                && (mine.memberCodes.contains($0.code) || $0.startDate < Self.ownerMemberRecordsSince)
        }
        let ownedCodes = Set(rooms.map(\.code))
        for code in Set(mine.memberCodes) where !have.contains(code) && !ownedCodes.contains(code) {
            // A room deleted since, or unreadable right now: skip it, the
            // next launch tries again.
            if let room = try? await roomSync.fetchRoom(code: code) { rooms.append(room) }
            guard isCurrentAccount(me.id, revision: revision), roomRestoration?.request == request,
                  !Task.isCancelled else { return }
        }
        guard !rooms.isEmpty else { return }
        // Newest first, as the list keeps them. Re-checked: a join may have
        // landed while the queries ran.
        for room in rooms.sorted(by: { $0.startDate > $1.startDate })
        where !challenges.contains(where: { $0.roomCode == room.code }) {
            challenges.append(challenge(mirroring: room))
        }
        print("[room] restored \(rooms.count) room(s) from the cloud")
    }

    private func challenge(mirroring room: CloudKitService.RemoteRoom) -> Challenge {
        Challenge(
            id: UUID(), title: room.title, startDate: room.startDate,
            cards: (1...cardCount(for: room.momentTitles)).map { DayCard(day: $0) },
            mode: room.mode, clipLength: room.clipLength,
            orientation: room.orientation,
            cameraStyle: room.cameraStyle,
            templateName: room.templateName,
            momentTitles: room.momentTitles,
            roomCode: room.code, ownerName: room.ownerName, ownerID: room.ownerID)
    }

    /// My own takes that are in the room but not on this phone — a new phone,
    /// a reinstall, a room put back by `restoreMyRooms` — become this phone's
    /// take 1 again. Left as empty cards, the camera filed the next take into
    /// the first "empty" moment and uploaded it over the one already there,
    /// for everyone. Only take 1: extra takes stay in the room as they are.
    @MainActor
    private func adoptMyTakes(_ remote: [CloudKitService.RemoteClip], code: String, into id: UUID) {
        guard let me = account?.account,
              let ci = challenges.firstIndex(where: { $0.id == id }) else { return }
        for clip in remote where clip.authorID == me.id
            && clip.id == CloudKitService.clipRecordName(code: code, authorID: me.id, day: clip.day) {
            guard let idx = challenges[ci].cards.firstIndex(where: { $0.day == clip.day }),
                  challenges[ci].cards[idx].clipFileName == nil,
                  let fileName = fileStore.storeClip(from: clip.localURL, day: clip.day, challengeID: id)
            else { continue }
            challenges[ci].cards[idx].clipFileName = fileName
            challenges[ci].cards[idx].recordedAt = clip.recordedAt
            challenges[ci].cards[idx].captions = clip.captions
        }
    }

    /// Join an existing room by its code, mirroring it locally.
    @MainActor
    @discardableResult
    func joinRoom(code: String) async throws -> Challenge {
        guard effects.allowsCloudRoomManagement else { throw IsolationError.cloudRoomManagementDisabled }
        guard let me = account?.account else { throw RoomError.notSignedIn }
        let revision = AccountStore.identityRevision
        try Task.checkCancellation()
        let normalized = InviteCode.normalize(code)
        // Already joined? Jump to it.
        if let existing = challenges.first(where: { $0.roomCode == normalized }) {
            return existing
        }
        // A code with an O in it, or five characters, isn't a room that exists
        // somewhere — it's a room that cannot exist. Say so here rather than
        // spending a round trip to be told the same thing, or worse, telling
        // someone to sign into iCloud because that's the error the trip hit
        // first.
        guard InviteCode.isValid(normalized) else {
            throw CloudKitService.CKServiceError.roomNotFound
        }
        let room = try await roomSync.fetchRoom(code: normalized)
        try Task.checkCancellation()
        guard isCurrentAccount(me.id, revision: revision) else { throw CancellationError() }
        // Six people at most (PRD 5.5). Counted from the `Member` records;
        // when those can't be read the join goes ahead rather than turning
        // somebody away on a guess.
        let people = await roomSync.peopleInRoom(code: normalized, ownerID: room.ownerID)
        try Task.checkCancellation()
        guard isCurrentAccount(me.id, revision: revision) else { throw CancellationError() }
        // Another join or restoration may have finished while the requests ran.
        if let existing = challenges.first(where: { $0.roomCode == normalized }) { return existing }
        if let people, !people.contains(me.id), people.count >= Self.roomCapacity {
            throw CloudKitService.CKServiceError.roomFull
        }
        let challenge = Challenge(
            id: UUID(), title: room.title, startDate: room.startDate,
            cards: (1...cardCount(for: room.momentTitles)).map { DayCard(day: $0) },
            mode: room.mode, clipLength: room.clipLength,
            orientation: room.orientation,
            cameraStyle: room.cameraStyle,
            templateName: room.templateName,
            momentTitles: room.momentTitles,
            roomCode: room.code, ownerName: room.ownerName, ownerID: room.ownerID)
        challenges.insert(challenge, at: 0)
        // Only once the room is really here: a code that found nothing never
        // reaches this line, so it leaves no record behind.
        await roomSync.recordMembership(
            code: room.code, authorID: me.id, displayName: me.displayName)
        try Task.checkCancellation()
        guard isCurrentAccount(me.id, revision: revision), self.challenge(challenge.id) != nil
        else { throw CancellationError() }
        // The room is joined; open it now. Putting my avatar and mood back
        // and pulling every clip (a busy room is dozens of videos) happen
        // behind it, so joining doesn't wait on downloads.
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentAccount(me.id, revision: revision) else { return }
            self.roomSync.forgetPublishedProfile(code: room.code)
            await self.publishMyProfile(toRoom: room.code)
            guard self.isCurrentAccount(me.id, revision: revision) else { return }
            await self.syncRoom(challenge.id)
        }
        return challenge
    }

    /// Pull every member's clips for a room into the local cache, send up any
    /// of mine the room is missing, then fold remote reactions/comments into
    /// the local cards.
    @MainActor
    func syncRoom(_ id: UUID) async {
        guard let challenge = challenge(id), let code = challenge.roomCode else { return }
        guard !effects.allowsCloudRoomManagement || account?.isSignedIn == true else { return }
        let userID = account?.account?.id
        let revision = AccountStore.identityRevision
        let isCurrent = {
            self.isCurrentAccount(userID, revision: revision)
                && self.challenge(id)?.roomCode == code && !Task.isCancelled
        }
        // Who is in the room first: last launch's roster at once, then a fresh
        // one, before the clip downloads that can take a while.
        roomSync.restoreCachedMembers(code: code)
        // Responses are independent of media downloads and uploads. A slow
        // friend's video must not hold back the room's comments and reactions.
        // Structured lifetime: sign-out/room changes still invalidate both paths.
        async let interactions: Void = syncRoomInteractions(
            id, code: code, userID: userID, revision: revision)
        await roomSync.syncMembers(code: code)
        guard isCurrent() else { return }
        if let remote = await roomSync.syncClips(code: code) {
            guard isCurrent() else { return }
            adoptMyTakes(remote, code: code, into: id)
            if await uploadMissingClips(in: challenge, code: code, remote: remote) {
                guard isCurrent() else { return }
                _ = await roomSync.syncClips(code: code)
            }
            guard isCurrent() else { return }
            await pushStaleCaptions(in: id, code: code, remote: remote)
        }
        guard isCurrent() else { return }
        await syncRoomTitle(id, code: code)
        await interactions
    }

    @MainActor
    private func syncRoomInteractions(
        _ id: UUID, code: String, userID: String?, revision: UInt64
    ) async {
        let isCurrent = {
            self.isCurrentAccount(userID, revision: revision)
                && self.challenge(id)?.roomCode == code && !Task.isCancelled
        }
        guard isCurrent() else { return }
        let request = UUID()
        interactionRequests[id] = request
        defer {
            if interactionRequests[id] == request { interactionRequests[id] = nil }
        }
        guard let interactions = await roomSync.fetchInteractions(code: code),
              isCurrent(), interactionRequests[id] == request else { return }
        let kept = keepingMyRecentInteractions(interactions, code: code)
        roomSync.remoteReactions[code] = kept.reactions
        roomSync.remoteComments[code] = kept.comments
        mergeInteractions(interactions, into: id)
    }

    private func isCurrentAccount(_ userID: String?, revision: UInt64) -> Bool {
        account?.account?.id == userID && AccountStore.identityRevision == revision
    }

    /// How long a reaction or comment I just added on a friend's take is kept
    /// on screen while the room's answer doesn't have it yet: the save may
    /// still be in flight, or saved but not yet in query results.
    static let myInteractionGrace: TimeInterval = 120

    /// The fetched interactions plus my own recent ones the fetch didn't
    /// return. Replacing them outright made a comment I had just typed vanish
    /// on the next poll and flicker back later — or never, if it failed.
    @MainActor
    private func keepingMyRecentInteractions(
        _ fetched: (reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment]),
        code: String, now: Date = .now
    ) -> (reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment]) {
        guard let me = account?.account?.id else { return fetched }
        let recent = { (date: Date) in now.timeIntervalSince(date) < Self.myInteractionGrace }
        var reactions = fetched.reactions
        for mine in roomSync.remoteReactions[code] ?? []
        where mine.authorID == me && recent(mine.createdAt)
            && !reactions.contains(where: {
                $0.authorID == me && $0.emoji == mine.emoji && $0.day == mine.day
                    && $0.targetAuthorID == mine.targetAuthorID
            }) {
            reactions.append(mine)
        }
        var comments = fetched.comments
        let ids = Set(comments.map(\.id))
        for mine in roomSync.remoteComments[code] ?? []
        where mine.authorID == me && recent(mine.createdAt) && !ids.contains(mine.id) {
            comments.append(mine)
        }
        return (reactions, comments)
    }

    /// Renames a room on this phone at once, then for everyone in it.
    @MainActor
    func renameRoom(_ id: UUID, to title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = challenges.firstIndex(where: { $0.id == id }),
              let code = challenges[index].roomCode
        else { return }
        challenges[index].title = title
        guard effects.allowsCloudRoomManagement, let me = account?.account else { return }
        await roomSync.publishRoomTitle(code: code, authorID: me.id, displayName: me.displayName, title: title)
    }

    /// Sends a rename that didn't get through, then takes the room's newest
    /// name from its members' records.
    @MainActor
    private func syncRoomTitle(_ id: UUID, code: String) async {
        if effects.allowsCloudRoomManagement, let me = account?.account {
            await roomSync.publishRoomTitle(code: code, authorID: me.id, displayName: me.displayName)
        }
        guard let latest = roomSync.latestRoomTitle(code: code),
              let index = challenges.firstIndex(where: { $0.id == id }),
              challenges[index].title != latest
        else { return }
        challenges[index].title = latest
    }

    /// Re-sends my takes the room doesn't have.
    ///
    /// `saveClip` uploads once, at record time. A take whose upload failed — no
    /// network, iCloud refusing the app — used to stay on this phone for good:
    /// shown to me as pending, to nobody else, and "retry sync" only pulled.
    /// Runs only after a fetch succeeded, so "missing" means missing rather
    /// than unreachable.
    ///
    /// - Returns: whether anything went up, so the caller can pull it back.
    @MainActor
    private func uploadMissingClips(
        in challenge: Challenge, code: String, remote: [CloudKitService.RemoteClip]
    ) async -> Bool {
        guard effects.allowsCloudRoomManagement, let me = account?.account else { return false }
        let revision = AccountStore.identityRevision
        // Keyed by take, not by day: a moment can hold several of my takes, and
        // the room having take 1 says nothing about take 2.
        let roomCopies = Dictionary(
            remote.filter { $0.authorID == me.id }
                .map { (Self.takeKey(day: $0.day, takeID: takeID(of: $0, code: code)), $0.recordedAt) },
            uniquingKeysWith: max)
        var uploadedAny = false
        for card in challenge.cards {
            guard isCurrentAccount(me.id, revision: revision),
                  self.challenge(challenge.id)?.roomCode == code, !Task.isCancelled else { return uploadedAny }
            guard let fileName = card.clipFileName else { continue }
            // Extra takes first in code, independent of take 1's fate below:
            // each is its own record, and a take never re-recorded in place, so
            // "the room has a record by this name" is the whole question.
            for take in card.moreTakes
            where roomCopies[Self.takeKey(day: card.day, takeID: take.id)] == nil {
                guard isCurrentAccount(me.id, revision: revision),
                      self.challenge(challenge.id)?.roomCode == code, !Task.isCancelled else { return uploadedAny }
                let file = fileStore.clipURL(fileName: take.fileName, challengeID: challenge.id)
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                if await roomSync.uploadClip(
                    code: code, day: card.day, authorID: me.id,
                    authorName: me.displayName, fileURL: file,
                    captions: take.captions,
                    recordedAt: take.recordedAt,
                    takeID: take.id
                ) {
                    uploadedAny = true
                }
            }
            guard isCurrentAccount(me.id, revision: revision),
                  self.challenge(challenge.id)?.roomCode == code, !Task.isCancelled else { return uploadedAny }
            // The room's copy carries the time its take was filmed (it used to
            // carry the time it went up). Same take: equal stamps, nothing to
            // do. A re-record whose upload failed: the card's take is later
            // than the one the room still holds, so it goes up. A copy written
            // by an older client is stamped at upload, which is after the take
            // it holds, so it still reads as "already there".
            if let roomCopy = roomCopies[Self.takeKey(day: card.day, takeID: nil)], roomCopy >= (card.recordedAt ?? .distantPast) {
                continue
            }
            let file = fileStore.clipURL(fileName: fileName, challengeID: challenge.id)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            if await roomSync.uploadClip(
                code: code, day: card.day, authorID: me.id,
                authorName: me.displayName, fileURL: file,
                captions: card.captions,
                // A card from before `recordedAt` existed has no better answer
                // than now; every card saved since has one.
                recordedAt: card.recordedAt ?? .now
            ) {
                uploadedAny = true
            }
        }
        return uploadedAny
    }

    /// Sends my captions again wherever the room's copy of my take says
    /// something else.
    ///
    /// A caption edited after the take goes up once, from
    /// `pushCaptionsToRoom`, and a failure there only logs. The take is
    /// already in the room, so no later upload carries the new words either:
    /// friends kept seeing the old caption for good. Comparing on every sync
    /// retries it until the room agrees.
    ///
    /// Words and placement only — the ids of captions rebuilt from
    /// `overlayText` are new every time. Without `captionsJSON` on the record
    /// (not deployed, or an older client wrote it) only the first caption's
    /// words can be compared, so only those count.
    @MainActor
    private func pushStaleCaptions(
        in id: UUID, code: String, remote: [CloudKitService.RemoteClip]
    ) async {
        guard effects.allowsCloudRoomManagement, let me = account?.account,
              let challenge = challenge(id) else { return }
        let revision = AccountStore.identityRevision
        for clip in remote where clip.authorID == me.id {
            guard isCurrentAccount(me.id, revision: revision), self.challenge(id)?.roomCode == code,
                  !Task.isCancelled else { return }
            let take = takeID(of: clip, code: code)
            guard let card = challenge.cards.first(where: { $0.day == clip.day }) else { continue }
            let local: [Caption]
            if let take {
                guard let extra = card.moreTakes.first(where: { $0.id == take }) else { continue }
                local = extra.captions.drawable
            } else {
                guard card.clipFileName != nil else { continue }
                local = card.captions.drawable
            }
            guard Self.captionsDiffer(local: local, remote: clip) else { continue }
            await roomSync.updateClipCaption(
                code: code, day: clip.day, authorID: me.id, captions: local, takeID: take)
        }
    }

    static func captionsDiffer(local: [Caption], remote: CloudKitService.RemoteClip) -> Bool {
        let theirs = remote.captions
        if local.firstText != theirs.firstText { return true }
        guard remote.captionsJSON != nil else { return false }
        return local.count != theirs.count
            || zip(local, theirs).contains { $0.trimmedText != $1.trimmedText || $0.sticker != $1.sticker }
    }

    /// Refreshes every locally joined room when the app becomes active.
    /// Board views also poll while visible so two friends recording at the
    /// same time see each other's clips without manual pull-to-refresh.
    ///
    /// A few rooms at a time rather than one after another: each room's sync is
    /// mostly waiting on CloudKit, and someone in five rooms used to wait for
    /// all five in a row. Each room still syncs in its own order inside
    /// `syncRoom`; the cap keeps a long room list from opening every request at
    /// once.
    @MainActor
    func syncSharedRooms() async {
        let ids = challenges.filter(\.isShared).map(\.id)
        var pending = ids.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<Self.sharedRoomSyncWidth {
                guard let id = pending.next() else { break }
                group.addTask { @MainActor in await self.syncRoom(id) }
            }
            while await group.next() != nil {
                guard let id = pending.next() else { continue }
                group.addTask { @MainActor in await self.syncRoom(id) }
            }
        }
    }

    /// How many rooms `syncSharedRooms` syncs at once.
    static let sharedRoomSyncWidth = 3

    /// Fold remote reactions/comments into local cards by day. Remote is the
    /// source of truth, unioned with my own optimistic writes not yet echoed
    /// back — so a reaction I just tapped stays visible before the next fetch.
    @MainActor
    private func mergeInteractions(
        _ remote: (reactions: [CloudKitService.RemoteReaction], comments: [CloudKitService.RemoteComment]),
        into id: UUID
    ) {
        guard let ci = challenges.firstIndex(where: { $0.id == id }) else { return }
        let myID = account?.account?.id
        for cardIdx in challenges[ci].cards.indices {
            let day = challenges[ci].cards[cardIdx].day

            var reactions = remote.reactions
                .filter { $0.day == day && $0.targetAuthorID == myID }
                .map { ClipReaction(emoji: $0.emoji, authorID: $0.authorID, authorName: $0.authorName, createdAt: $0.createdAt) }
            for mine in challenges[ci].cards[cardIdx].reactions where mine.authorID == myID {
                if !reactions.contains(where: { $0.id == mine.id }) { reactions.append(mine) }
            }
            challenges[ci].cards[cardIdx].reactions = reactions

            var comments = remote.comments
                .filter { $0.day == day && $0.targetAuthorID == myID }
                .compactMap { rc -> ClipComment? in
                    guard let uuid = UUID(uuidString: rc.id) else { return nil }
                    return ClipComment(id: uuid, text: rc.text, authorID: rc.authorID, authorName: rc.authorName, createdAt: rc.createdAt)
                }
            for mine in challenges[ci].cards[cardIdx].comments where mine.authorID == myID {
                if !comments.contains(where: { $0.id == mine.id }) { comments.append(mine) }
            }
            challenges[ci].cards[cardIdx].comments = comments.sorted { $0.createdAt < $1.createdAt }
        }
    }

    /// Members seen in a room: owner + everyone who has uploaded a clip + me.
    /// Puts a clip into a room. A room is filmed whenever, so it is never
    /// full: the first empty slot, else one more take on the last one.
    @discardableResult
    func sendToRoom(
        from url: URL, roomID: UUID, overlayText: String? = nil,
        captions: [Caption]? = nil, recordedAt: Date = .now
    ) -> Bool {
        guard let room = challenge(roomID), room.isShared, let last = room.cards.last?.day else { return false }
        if let day = ClipFiling.targetDay(in: room) {
            saveClip(from: url, day: day, challengeID: roomID, overlayText: overlayText,
                     captions: captions, recordedAt: recordedAt)
        } else {
            saveClip(from: url, day: last, challengeID: roomID, overlayText: overlayText,
                     captions: captions, recordedAt: recordedAt, take: .append)
        }
        return true
    }

    /// Today's plan — my own one-day story with a list, made today. There
    /// is at most one a day; this is it.
    func todaysPlan(now: Date = .now, calendar: Calendar = .current) -> Challenge? {
        plan(on: now, calendar: calendar)
    }

    /// The plan written for `day`, if there is one.
    func plan(on day: Date, calendar: Calendar = .current) -> Challenge? {
        let now = day
        return challenges.first {
            !$0.isShared && !$0.isTimeOnly && $0.momentTitles?.isEmpty == false
                && calendar.isDate($0.startDate, inSameDayAs: now)
        }
    }

    /// The most people a room takes.
    static let roomCapacity = 6

    func members(for challengeID: UUID) -> [(id: String, name: String)] {
        guard let challenge = challenge(challengeID), let code = challenge.roomCode else { return [] }
        var seen: [String: String] = [:]
        // The owner belongs in the roster before they've filmed anything —
        // otherwise someone who just joined sees a room with only themselves
        // in it and can't tell whether the code worked.
        if let ownerName = challenge.ownerName {
            seen[challenge.ownerID ?? ownerName] = ownerName
        }
        // Everyone with a `Member` record: joined, maybe not filmed yet.
        for member in (roomSync.remoteMembers[code] ?? [:]).values
        where !member.displayName.isEmpty || seen[member.userID] == nil {
            seen[member.userID] = member.displayName
        }
        // A take uploaded while its author's name was unknown carries none;
        // it mustn't blank the name their `Member` record has.
        for clip in roomSync.remoteClips[code] ?? [] where !clip.authorName.isEmpty || seen[clip.authorID] == nil {
            seen[clip.authorID] = clip.authorName
        }
        if let me = account?.account { seen[me.id] = me.displayName }
        // Rooms saved before `ownerID` existed key the owner by name; drop that
        // placeholder once the same person turns up under a real author id.
        if challenge.ownerID == nil, let ownerName = challenge.ownerName,
           seen.contains(where: { $0.key != ownerName && $0.value == ownerName }) {
            seen.removeValue(forKey: ownerName)
        }
        return seen.map { (id: $0.key, name: $0.value) }.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
    }

    /// Signs out and forgets what the rooms had downloaded.
    ///
    /// The cache is keyed by author id, and signing out changes who I am. Left
    /// in place, my own uploaded clips became somebody else's: the roster still
    /// listed me, every empty slot read "waiting for <my own name>", and the
    /// header credited my takes to a stranger. The stories stay; only the
    /// borrowed copy of other people's work goes.
    func signOut() {
        for challenge in challenges {
            if let code = challenge.roomCode { roomSync.clearRoom(code) }
        }
        account?.signOut()
    }

    // MARK: - Account deletion

    /// Removes the person from the app entirely: their clips and interactions
    /// in every shared room they're part of, then every local story, clip file
    /// and preference on this device.
    ///
    /// Required by App Store guideline 5.1.1(v) — an app that creates accounts
    /// has to let you delete one. Signing out is not the same thing.
    @MainActor
    func deleteAccountAndAllData() async {
        // Preview teardown is owned by its runtime, never by account deletion.
        guard effects.allowsCloudRoomManagement else { return }
        if let me = account?.account {
            // Everything this person authored, addressed by reconstructable
            // record IDs rather than a query. See `deleteMyRoomData`.
            var clips: [(code: String, day: Int)] = []
            var reactions: [(code: String, targetAuthorID: String, day: Int, emoji: String)] = []
            var commentIDs: [String] = []
            var roomCodes: [String] = []
            var otherRecordNames: [String] = []

            for challenge in challenges {
                guard let code = challenge.roomCode else { continue }
                roomCodes.append(code)
                for card in challenge.cards {
                    clips.append((code, card.day))
                }
                otherRecordNames += extraTakeRecordNames(in: challenge, authorID: me.id)
                for reaction in roomSync.remoteReactions[code] ?? []
                where reaction.authorID == me.id {
                    reactions.append((code, reaction.targetAuthorID, reaction.day, reaction.emoji))
                }
                for comment in roomSync.remoteComments[code] ?? []
                where comment.authorID == me.id {
                    commentIDs.append(comment.id)
                }
                // My own comments on my own clips live only on the card.
                for card in challenge.cards {
                    for comment in card.comments where comment.authorID == me.id {
                        commentIDs.append(comment.id.uuidString)
                    }
                }
            }

            try? await CloudKitService.deleteMyRoomData(
                authorID: me.id,
                clips: clips,
                reactions: reactions,
                commentIDs: commentIDs,
                roomCodes: roomCodes,
                otherRecordNames: otherRecordNames)
        }

        await wipeLocalAccountData()
    }

    /// Record names of every extra take of mine in a room — names
    /// `deleteMyRoomData` and `AccountDeletionService.inventory` can't rebuild
    /// from a day alone, the way they rebuild take 1's.
    ///
    /// The ones this phone filmed, from the cards, and any the room is known to
    /// hold that this phone doesn't — filmed on another device signed in as me.
    /// Sorted and unique, so a resumed deletion pages the same list.
    func extraTakeRecordNames(in challenge: Challenge, authorID: String) -> [String] {
        guard let code = challenge.roomCode else { return [] }
        var names: Set<String> = []
        for card in challenge.cards {
            for take in card.moreTakes {
                names.insert(CloudKitService.clipRecordName(
                    code: code, authorID: authorID, day: card.day, takeID: take.id))
            }
        }
        for clip in roomSync.remoteClips[code] ?? [] where clip.authorID == authorID
            && CloudKitService.takeID(fromClipRecordName: clip.id, code: code,
                                      authorID: authorID, day: clip.day) != nil {
            names.insert(clip.id)
        }
        return names.sorted()
    }

    /// The device half of account deletion: every stored clip, story, cover and
    /// preference, then the sign-out.
    ///
    /// Separated from the cloud half so `AccountDeletionService` can hold it
    /// back until the remote records are confirmed gone. Running it first, as
    /// the older path did, destroys the only copy of the inventory a retry
    /// would need — and leaves someone signed out, with their clips still on
    /// CloudKit, told they were deleted.
    ///
    /// Idempotent: the coordinator can replay this step after a crash between
    /// the wipe and the journal write.
    @MainActor
    func wipeLocalAccountData() async {
        for challenge in challenges {
            fileStore.deleteClips(challengeID: challenge.id)
            if let code = challenge.roomCode { roomSync.clearRoom(code) }
        }
        challenges = []
        account?.signOut()
        effects.resetNotificationPreferences()
    }

    func delete(_ id: UUID) {
        fileStore.deleteClips(challengeID: id)
        if let code = challenge(id)?.roomCode {
            // Leaving takes me out for everyone (1.5): my takes and my
            // `Member` record go too, so friends stop seeing my frame. The
            // room itself stays for them.
            if effects.allowsCloudRoomManagement, let me = account?.account {
                let sync = roomSync
                Task { @MainActor in await sync.leaveRemotely(code: code, authorID: me.id) }
            }
            roomSync.clearRoom(code)
        }
        challenges.removeAll { $0.id == id }
    }

    /// Moves a freshly recorded clip into permanent storage and marks the card done.
    ///
    /// `recordedAt` is when the take was filmed. Straight from the camera that
    /// is now; a draft filed later has its own time and passes it, otherwise
    /// the card — and every friend's copy of it — says the moment happened
    /// when somebody tidied their drafts.
    ///
    /// `take` only matters when the moment already has a clip. The default,
    /// `.replace(nil)`, is 重拍 on take 1 and what every caller did before a
    /// moment could hold more than one take; only 再拍一段 passes `.append`.
    func saveClip(
        from tempURL: URL,
        day: Int,
        challengeID: UUID,
        overlayText: String? = nil,
        captions: [Caption]? = nil,
        recordedAt: Date = .now,
        take: TakeTarget = .replace(nil)
    ) {
        // A draft filed into a story brings every caption it had; the camera
        // hands over the one line typed while filming.
        let captions = (captions ?? .single(overlayText)).drawable
        guard let ci = challenges.firstIndex(where: { $0.id == challengeID }) else { return }
        guard let idx = challenges[ci].cards.firstIndex(where: { $0.day == day }) else { return }

        // 重拍 replaces the take you were looking at, file and room record
        // both, so friends see the new one in its place. 再拍一段 keeps every
        // take and adds the new one under its own file and its own record;
        // take 1 stays exactly where every version of the app expects it.
        let card = challenges[ci].cards[idx]
        let extraIndex: Int? = switch take {
        case .replace(let id?): card.moreTakes.firstIndex { $0.id == id }
        case .replace(nil), .append: nil
        }
        let writesTakeOne = card.clipFileName == nil || take == .replace(nil)

        let fileName: String
        let takeID: UUID?
        if writesTakeOne {
            guard let stored = fileStore.storeClip(from: tempURL, day: day, challengeID: challengeID) else { return }
            fileName = stored
            takeID = nil
            challenges[ci].cards[idx].clipFileName = fileName
            challenges[ci].cards[idx].recordedAt = recordedAt
            challenges[ci].cards[idx].captions = captions
        } else if let t = extraIndex {
            // Same take id, so the same file name and the same room record.
            let id = card.moreTakes[t].id
            guard let stored = fileStore.storeExtraTake(
                from: tempURL, day: day, takeID: id, challengeID: challengeID) else { return }
            fileName = stored
            takeID = id
            challenges[ci].cards[idx].moreTakes[t].fileName = stored
            challenges[ci].cards[idx].moreTakes[t].recordedAt = recordedAt
            challenges[ci].cards[idx].moreTakes[t].captions = captions
        } else {
            // 再拍一段 — or 重拍 on a take that was gone by the time the camera
            // handed back, where keeping the footage beats dropping it.
            let id = UUID()
            // `storeExtraTake` never deletes; nil means nothing was kept, and
            // nothing is touched — never "fall back" to `storeClip`, which
            // clears `dayN.*` first.
            guard let stored = fileStore.storeExtraTake(
                from: tempURL, day: day, takeID: id, challengeID: challengeID) else { return }
            fileName = stored
            takeID = id
            challenges[ci].cards[idx].moreTakes.append(ClipTake(
                id: id, fileName: stored, recordedAt: recordedAt,
                captions: captions))
        }

        // Shared room: also push this clip to CloudKit for friends to see.
        if let code = challenges[ci].roomCode, let me = account?.account {
            let dest = fileStore.clipURL(fileName: fileName, challengeID: challengeID)
            Task { @MainActor in
                if await roomSync.uploadClip(
                    code: code, day: day, authorID: me.id,
                    authorName: me.displayName, fileURL: dest,
                    captions: captions, recordedAt: recordedAt,
                    takeID: takeID
                ) {
                    await syncRoom(challengeID)
                }
            }
        }
    }

    func clipURL(for card: DayCard, in challengeID: UUID) -> URL? {
        guard let name = card.clipFileName else { return nil }
        return fileStore.clipURL(fileName: name, challengeID: challengeID)
    }

    /// Edit a clip's center caption after the fact (from the preview).
    ///
    /// Pushed to the room as well, not just saved locally. It used to say
    /// "room sync of caption edits rides the next clip upload", which in
    /// practice meant never: most captions are written *after* the take, so a
    /// friend saw the words you typed at record time and nothing you changed
    /// afterwards — including a caption you deleted.
    ///
    /// `takeID` nil is take 1 (the card's own fields); otherwise the extra take
    /// with that id. A take id the card doesn't have changes nothing — it must
    /// not land on take 1, whose words are somebody else's take.
    func updateOverlayText(_ text: String?, day: Int, challengeID: UUID, takeID: UUID? = nil) {
        guard let ci = challenges.firstIndex(where: { $0.id == challengeID }),
              let idx = challenges[ci].cards.firstIndex(where: { $0.day == day })
        else { return }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed?.isEmpty == true ? nil : trimmed
        if let takeID {
            guard let t = challenges[ci].cards[idx].moreTakes.firstIndex(where: { $0.id == takeID })
            else { return }
            challenges[ci].cards[idx].moreTakes[t].overlayText = words
            if words == nil { challenges[ci].cards[idx].moreTakes[t].captionSticker = nil }
        } else {
            challenges[ci].cards[idx].overlayText = words
            // Clearing the words clears where they were. Otherwise a caption
            // deleted and typed again would reappear wherever the last one was
            // dragged to, which reads as the app remembering something you
            // threw away.
            if words == nil { challenges[ci].cards[idx].captionSticker = nil }
        }
        pushCaptionsToRoom(day: day, takeID: takeID, challengeIndex: ci)
    }

    /// Every caption on one take at once — what the full-screen editor saves
    /// after each change. Blank ones are dropped. `takeID` as in
    /// `updateOverlayText`; pushed to the room the same way.
    func updateCaptions(_ captions: [Caption], day: Int, challengeID: UUID, takeID: UUID? = nil) {
        guard let ci = challenges.firstIndex(where: { $0.id == challengeID }),
              let idx = challenges[ci].cards.firstIndex(where: { $0.day == day })
        else { return }
        let kept = captions.drawable
        if let takeID {
            guard let t = challenges[ci].cards[idx].moreTakes.firstIndex(where: { $0.id == takeID })
            else { return }
            guard challenges[ci].cards[idx].moreTakes[t].captions != kept else { return }
            challenges[ci].cards[idx].moreTakes[t].captions = kept
        } else {
            guard challenges[ci].cards[idx].captions != kept else { return }
            challenges[ci].cards[idx].captions = kept
        }
        pushCaptionsToRoom(day: day, takeID: takeID, challengeIndex: ci)
    }

    /// Where the caption sits on the clip, and how it's drawn.
    ///
    /// Written on every drag, so it takes the finished sticker rather than a
    /// delta — the gesture owns the arithmetic, the card owns the result.
    /// `takeID` as in `updateOverlayText`.
    func updateCaptionSticker(_ sticker: CaptionSticker?, day: Int, challengeID: UUID, takeID: UUID? = nil) {
        guard let ci = challenges.firstIndex(where: { $0.id == challengeID }),
              let idx = challenges[ci].cards.firstIndex(where: { $0.day == day })
        else { return }
        if let takeID {
            guard let t = challenges[ci].cards[idx].moreTakes.firstIndex(where: { $0.id == takeID })
            else { return }
            challenges[ci].cards[idx].moreTakes[t].captionSticker = sticker
        } else {
            challenges[ci].cards[idx].captionSticker = sticker
        }
    }

    /// Sends a take's captions to the room, when there is one to send to.
    ///
    /// Every caption, position and look included — `captionsJSON` carries
    /// them, `overlayText` carries the first one's words for 1.5 (31). Read
    /// off the card when the push is made, so it sends what is saved now.
    private func pushCaptionsToRoom(day: Int, takeID: UUID?, challengeIndex ci: Int) {
        guard let code = challenges[ci].roomCode, let me = account?.account,
              let card = challenges[ci].cards.first(where: { $0.day == day })
        else { return }
        let captions = takeID.map { id in
            card.moreTakes.first { $0.id == id }?.captions ?? []
        } ?? card.captions
        Task { @MainActor in
            await roomSync.updateClipCaption(
                code: code, day: day, authorID: me.id, captions: captions, takeID: takeID)
        }
    }

    // MARK: - Reactions & comments (local-first)

    /// The identity a reaction/comment is attributed to. Falls back to a local
    /// stand-in so solo ("just me") challenges work without Sign in with Apple.
    var currentAuthor: (id: String, name: String) {
        if let me = account?.account { return (me.id, me.displayName) }
        return ("local", "You")
    }

    /// Toggle one emoji on a day's clip for the current author. Optimistic
    /// local write; a shared room also mirrors it to CloudKit (best-effort).
    func toggleReaction(_ emoji: String, day: Int, challengeID: UUID, targetAuthorID: String) {
        let me = currentAuthor
        let isMe = targetAuthorID == me.id || targetAuthorID == "local"
        let nowOn: Bool

        if isMe {
            guard let ci = challenges.firstIndex(where: { $0.id == challengeID }),
                  let idx = challenges[ci].cards.firstIndex(where: { $0.day == day }) else { return }
            var reactions = challenges[ci].cards[idx].reactions
            if let hit = reactions.firstIndex(where: { $0.authorID == me.id && $0.emoji == emoji }) {
                reactions.remove(at: hit)
                nowOn = false
            } else {
                reactions.append(ClipReaction(emoji: emoji, authorID: me.id, authorName: me.name))
                nowOn = true
            }
            challenges[ci].cards[idx].reactions = reactions
        } else {
            guard let code = challenge(challengeID)?.roomCode else { return }
            var remoteR = roomSync.remoteReactions[code] ?? []
            let existingIdx = remoteR.firstIndex { $0.authorID == me.id && $0.emoji == emoji && $0.targetAuthorID == targetAuthorID && $0.day == day }
            if let existingIdx {
                remoteR.remove(at: existingIdx)
                nowOn = false
            } else {
                remoteR.append(.init(day: day, emoji: emoji, authorID: me.id, authorName: me.name, targetAuthorID: targetAuthorID, createdAt: .now))
                nowOn = true
            }
            roomSync.remoteReactions[code] = remoteR
        }

        if let code = challenge(challengeID)?.roomCode, let acct = account?.account {
            Task { @MainActor in
                await roomSync.setReaction(
                    code: code, day: day, authorID: acct.id, authorName: acct.displayName,
                    targetAuthorID: targetAuthorID, emoji: emoji, on: nowOn)
            }
        }
    }

    // MARK: - 拍一拍

    /// Whether I already poked this friend in this room today.
    func hasPokedToday(challengeID: UUID, targetAuthorID: String) -> Bool {
        guard let code = challenge(challengeID)?.roomCode else { return false }
        return PokeLimiter().hasPoked(code: code, targetAuthorID: targetAuthorID)
    }

    /// Nudge a friend who hasn't filmed today. Once per friend per day; the
    /// CloudKit write is best-effort like a reaction's.
    @discardableResult
    func poke(challengeID: UUID, targetAuthorID: String) -> Bool {
        guard let code = challenge(challengeID)?.roomCode,
              let acct = account?.account, targetAuthorID != acct.id,
              PokeLimiter().claim(code: code, targetAuthorID: targetAuthorID)
        else { return false }
        Task { @MainActor in
            // Not sent, not used: the button turns back so it can be tried
            // again, instead of saying "poked" until tomorrow over nothing.
            if await !roomSync.sendPoke(
                code: code, authorID: acct.id, authorName: acct.displayName,
                targetAuthorID: targetAuthorID) {
                PokeLimiter().release(code: code, targetAuthorID: targetAuthorID)
            }
        }
        return true
    }

    /// Append a comment to a day's clip. Empty/whitespace-only text is ignored.
    func addComment(_ text: String, day: Int, challengeID: UUID, targetAuthorID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let me = currentAuthor
        let isMe = targetAuthorID == me.id || targetAuthorID == "local"
        let comment = ClipComment(text: trimmed, authorID: me.id, authorName: me.name)

        if isMe {
            guard let ci = challenges.firstIndex(where: { $0.id == challengeID }),
                  let idx = challenges[ci].cards.firstIndex(where: { $0.day == day }) else { return }
            challenges[ci].cards[idx].comments.append(comment)
        } else {
            guard let code = challenge(challengeID)?.roomCode else { return }
            var remoteC = roomSync.remoteComments[code] ?? []
            remoteC.append(.init(id: comment.id.uuidString, day: day, text: trimmed, authorID: me.id, authorName: me.name, targetAuthorID: targetAuthorID, createdAt: comment.createdAt))
            roomSync.remoteComments[code] = remoteC
        }

        if let code = challenge(challengeID)?.roomCode, let acct = account?.account {
            Task { @MainActor in
                await roomSync.postComment(
                    code: code, day: day, id: comment.id.uuidString,
                    text: trimmed, authorID: acct.id, authorName: acct.displayName, targetAuthorID: targetAuthorID)
            }
        }
    }

    /// Remove one of the current author's own comments.
    func deleteComment(_ commentID: UUID, day: Int, challengeID: UUID, targetAuthorID: String) {
        let me = currentAuthor
        let isMe = targetAuthorID == me.id || targetAuthorID == "local"

        if isMe {
            guard let ci = challenges.firstIndex(where: { $0.id == challengeID }),
                  let idx = challenges[ci].cards.firstIndex(where: { $0.day == day }) else { return }
            challenges[ci].cards[idx].comments.removeAll { $0.id == commentID && $0.authorID == me.id }
        } else {
            guard let code = challenge(challengeID)?.roomCode else { return }
            var remoteC = roomSync.remoteComments[code] ?? []
            remoteC.removeAll { $0.id == commentID.uuidString && $0.authorID == me.id }
            roomSync.remoteComments[code] = remoteC
        }

        if challenge(challengeID)?.roomCode != nil, account?.account != nil {
            Task { @MainActor in
                await roomSync.deleteComment(id: commentID.uuidString)
            }
        }
    }

    /// All recorded clips in day order — the stitcher's input. For a shared
    /// room this merges every member's clips with my own local ones.
    ///
    /// The local half is not a fallback for an unsynced room: it is the only
    /// record of a clip whose upload hasn't landed yet. Returning the remote
    /// list alone made a moment I had just filmed offline disappear from the
    /// room, the home card and the count, and come back only after a relaunch.
    func recordedClips(for challengeID: UUID) -> [DayClip] {
        guard let challenge = challenge(challengeID) else { return [] }
        let presenter = ChallengePresenter(challenge: challenge)
        if let code = challenge.roomCode,
           let remote = roomSync.remoteClips[code], !remote.isEmpty {
            let remoteReactions = roomSync.remoteReactions[code] ?? []
            let remoteComments = roomSync.remoteComments[code] ?? []
            let myID = account?.account?.id
            // Takes of mine the room already has, by record name — a day is no
            // longer enough, since one moment can hold several of my takes and
            // the room can have take 1 while take 2 is still only here.
            // Anything else I've filmed belongs in the list once.
            let uploaded = Set(remote.filter { $0.authorID == myID }
                .map { Self.takeKey(day: $0.day, takeID: takeID(of: $0, code: code)) })
            let pending = localClips(in: challenge, presenter: presenter)
                .filter { !uploaded.contains(Self.takeKey(day: $0.day, takeID: $0.takeID)) }
            return (remote
                .map { clip in
                    let isMe = clip.authorID == (account?.account?.id ?? "")
                    let card = isMe ? challenge.cards.first { c in c.day == clip.day } : nil
                    let take = takeID(of: clip, code: code)
                    // Reactions and comments are addressed to a person's
                    // moment, not to one take of it, so they ride take 1 only —
                    // on every take, the film would float the same 🔥 twice.
                    let carriesInteractions = take == nil
                    // My own words come off this phone's card: it is where
                    // they were edited, and until `captionsJSON` is deployed
                    // the room's copy only knows the first one.
                    let localCaptions: [Caption]?
                    if !isMe {
                        localCaptions = nil
                    } else if let take {
                        localCaptions = card?.moreTakes.first { $0.id == take }?.captions
                    } else {
                        localCaptions = card?.captions
                    }

                    let emojis = !carriesInteractions ? [] : isMe
                        ? (card?.reactions.map(\.emoji) ?? [])
                        : remoteReactions.filter { $0.day == clip.day && $0.targetAuthorID == clip.authorID }.map(\.emoji)

                    let commentLines = !carriesInteractions ? [] : isMe
                        ? (card.map(Self.commentLines(for:)) ?? [])
                        : remoteComments
                            .filter { $0.day == clip.day && $0.targetAuthorID == clip.authorID }
                            .sorted { $0.createdAt < $1.createdAt }
                            .map { "\($0.authorName): \($0.text)" }

                    return DayClip(
                        day: clip.day, url: clip.localURL, authorName: clip.authorName,
                        authorID: clip.authorID,
                        label: challenge.isTimeOnly ? nil : presenter.title(forSlot: clip.day),
                        captions: localCaptions ?? clip.captions,
                        recordedAt: clip.recordedAt,
                        emoji: emojis,
                        comments: commentLines,
                        key: clip.id,
                        takeID: take)
                } + pending)
                // Stable within a person's moment too: take 1, then the
                // others in the order they were filmed.
                .sorted {
                    ($0.day, $0.authorName ?? "", $0.takeID == nil ? 0 : 1, $0.recordedAt ?? .distantPast)
                        < ($1.day, $1.authorName ?? "", $1.takeID == nil ? 0 : 1, $1.recordedAt ?? .distantPast)
                }
        }
        return localClips(in: challenge, presenter: presenter)
    }

    /// Which take a room clip is, read off its record name. Nil for take 1 —
    /// and for any name this app didn't write, which is how every clip from
    /// before takes existed reads.
    private func takeID(of clip: CloudKitService.RemoteClip, code: String) -> UUID? {
        CloudKitService.takeID(
            fromClipRecordName: clip.id, code: code, authorID: clip.authorID, day: clip.day)
    }

    /// One string per take of one moment: the room copy and the local copy of
    /// the same take derive the same one.
    private static func takeKey(day: Int, takeID: UUID?) -> String {
        "\(day)#\(takeID?.uuidString ?? "1")"
    }

    /// My own clips, from the cards on this device: one per take, take 1 first.
    private func localClips(
        in challenge: Challenge, presenter: ChallengePresenter
    ) -> [DayClip] {
        challenge.cards.flatMap { card -> [DayClip] in
            // Extra takes only ever exist beside a take 1; a card whose take 1
            // file name is gone has nothing to show.
            guard let first = clipURL(for: card, in: challenge.id) else { return [] }
            let authorName = account?.account?.displayName
            let authorID = account?.account?.id ?? RoomProgress.soloAuthorID
            let label = challenge.isTimeOnly ? nil : presenter.title(forSlot: card.day)
            let takeOne = DayClip(
                day: card.day,
                url: first,
                authorName: authorName,
                authorID: authorID,
                label: label,
                captions: card.captions,
                recordedAt: card.recordedAt,
                emoji: card.reactions.map(\.emoji),
                comments: Self.commentLines(for: card))
            // Keyed apart from take 1's "dayN" — `DayClip.id` feeds SwiftUI
            // `ForEach`, and two clips with one id is one clip on screen.
            // Interactions stay on take 1 (see `recordedClips`).
            let others = card.moreTakes.map { take in
                DayClip(
                    day: card.day,
                    url: fileStore.clipURL(fileName: take.fileName, challengeID: challenge.id),
                    authorName: authorName,
                    authorID: authorID,
                    label: label,
                    captions: take.captions,
                    recordedAt: take.recordedAt,
                    key: "day\(card.day)_\(take.id.uuidString)",
                    takeID: take.id)
            }
            return [takeOne] + others
        }
    }

    func interactions(for challengeID: UUID, day: Int, targetAuthorID: String) -> (reactions: [ClipReaction], comments: [ClipComment]) {
        let me = account?.account?.id ?? "local"
        let isMe = targetAuthorID == me || targetAuthorID == "local"
        
        if isMe {
            guard let challenge = challenge(challengeID),
                  let card = challenge.cards.first(where: { $0.day == day }) else { return ([], []) }
            return (card.reactions, card.comments.sorted { $0.createdAt < $1.createdAt })
        } else {
            guard let code = challenge(challengeID)?.roomCode else { return ([], []) }
            let r = (roomSync.remoteReactions[code] ?? [])
                .filter { $0.day == day && $0.targetAuthorID == targetAuthorID }
                .map { ClipReaction(emoji: $0.emoji, authorID: $0.authorID, authorName: $0.authorName, createdAt: $0.createdAt) }
            let c = (roomSync.remoteComments[code] ?? [])
                .filter { $0.day == day && $0.targetAuthorID == targetAuthorID }
                .compactMap { rc -> ClipComment? in
                    guard let id = UUID(uuidString: rc.id) else { return nil }
                    return ClipComment(id: id, text: rc.text, authorID: rc.authorID, authorName: rc.authorName, createdAt: rc.createdAt)
                }
                .sorted { $0.createdAt < $1.createdAt }
            return (r, c)
        }
    }

    /// "Mia: this is great" lines, oldest first — the stitcher caps how many
    /// make it onto the frame.
    private static func commentLines(for card: DayCard) -> [String] {
        card.comments
            .sorted { $0.createdAt < $1.createdAt }
            .map { "\($0.authorName): \($0.text)" }
    }

    /// Card count for a new challenge: matches a custom moment list's length,
    /// falling back to the original 7-day/7-moment shape.
    private func cardCount(for momentTitles: [String]?) -> Int {
        guard let count = momentTitles?.count, count > 0 else { return 7 }
        return count
    }
}
