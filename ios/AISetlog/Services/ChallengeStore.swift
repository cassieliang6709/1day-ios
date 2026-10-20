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

    /// CloudKit room sync (remote clip cache + syncing spinners live there).
    let roomSync: RoomSyncService

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

    @discardableResult
    func create(
        title: String,
        mode: Challenge.Mode = .sevenDay,
        clipLength: Challenge.ClipLength = .tiny,
        orientation: Challenge.Orientation = .portrait,
        cameraStyle: CameraStyle? = nil,
        templateName: String? = nil,
        momentTitles: [String]? = nil
    ) -> Challenge {
        let challenge = Challenge(
            id: UUID(),
            title: title,
            startDate: .now,
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
        // The room I made has no `Member` record for me until this writes one.
        await publishMyProfile(toRoom: room.code)
        return challenge
    }

    /// Join an existing room by its code, mirroring it locally.
    @MainActor
    @discardableResult
    func joinRoom(code: String) async throws -> Challenge {
        guard effects.allowsCloudRoomManagement else { throw IsolationError.cloudRoomManagementDisabled }
        guard let me = account?.account else { throw RoomError.notSignedIn }
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
        // Joining wrote the record from scratch; put my avatar and mood back.
        roomSync.forgetPublishedProfile(code: room.code)
        await publishMyProfile(toRoom: room.code)
        await syncRoom(challenge.id)
        return challenge
    }

    /// Pull every member's clips for a room into the local cache, send up any
    /// of mine the room is missing, then fold remote reactions/comments into
    /// the local cards.
    @MainActor
    func syncRoom(_ id: UUID) async {
        guard let challenge = challenge(id), let code = challenge.roomCode else { return }
        if let remote = await roomSync.syncClips(code: code),
           await uploadMissingClips(in: challenge, code: code, remote: remote) {
            _ = await roomSync.syncClips(code: code)
        }
        if let interactions = await roomSync.fetchInteractions(code: code) {
            roomSync.remoteReactions[code] = interactions.reactions
            roomSync.remoteComments[code] = interactions.comments
            mergeInteractions(interactions, into: id)
        }
        await roomSync.syncMembers(code: code)
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
        // Keyed by take, not by day: a moment can hold several of my takes, and
        // the room having take 1 says nothing about take 2.
        let roomCopies = Dictionary(
            remote.filter { $0.authorID == me.id }
                .map { (Self.takeKey(day: $0.day, takeID: takeID(of: $0, code: code)), $0.recordedAt) },
            uniquingKeysWith: max)
        var uploadedAny = false
        for card in challenge.cards {
            guard let fileName = card.clipFileName else { continue }
            // Extra takes first in code, independent of take 1's fate below:
            // each is its own record, and a take never re-recorded in place, so
            // "the room has a record by this name" is the whole question.
            for take in card.moreTakes
            where roomCopies[Self.takeKey(day: card.day, takeID: take.id)] == nil {
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

    /// Refreshes every locally joined room when the app becomes active.
    /// Board views also poll while visible so two friends recording at the
    /// same time see each other's clips without manual pull-to-refresh.
    @MainActor
    func syncSharedRooms() async {
        let ids = challenges.filter(\.isShared).map(\.id)
        for id in ids {
            await syncRoom(id)
        }
    }

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
    func members(for challengeID: UUID) -> [(id: String, name: String)] {
        guard let challenge = challenge(challengeID), let code = challenge.roomCode else { return [] }
        var seen: [String: String] = [:]
        // The owner belongs in the roster before they've filmed anything —
        // otherwise someone who just joined sees a room with only themselves
        // in it and can't tell whether the code worked.
        if let ownerName = challenge.ownerName {
            seen[challenge.ownerID ?? ownerName] = ownerName
        }
        for clip in roomSync.remoteClips[code] ?? [] { seen[clip.authorID] = clip.authorName }
        if let me = account?.account { seen[me.id] = me.displayName }
        // Rooms saved before `ownerID` existed key the owner by name; drop that
        // placeholder once the same person turns up under a real author id.
        if challenge.ownerID == nil, let ownerName = challenge.ownerName,
           seen.contains(where: { $0.key != ownerName && $0.value == ownerName }) {
            seen.removeValue(forKey: ownerName)
        }
        return seen.map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
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
            // Leaves the room locally; the shared record stays for others.
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
            await roomSync.sendPoke(
                code: code, authorID: acct.id, authorName: acct.displayName,
                targetAuthorID: targetAuthorID)
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
