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
            ReminderService.reconcile(for: challenges)
            let oldRooms = Set(oldValue.compactMap(\.roomCode))
            let newRooms = Set(challenges.compactMap(\.roomCode))
            if oldRooms != newRooms {
                SharedActivityNotificationService.reconcileSubscriptions(for: challenges)
            }
        }
    }

    var customTemplates: [ChallengeTemplate] = [] {
        didSet { repository.saveTemplates(customTemplates) }
    }

    /// Set once at app launch so shared rooms can attribute + upload clips.
    var account: AccountStore?

    /// CloudKit room sync (remote clip cache + syncing spinners live there).
    let roomSync: RoomSyncService

    private let repository: ChallengeRepository
    private let fileStore: ClipFileStore

    init(repository: ChallengeRepository? = nil,
         fileStore: ClipFileStore = DiskClipFileStore(),
         roomSync: RoomSyncService? = nil) {
        self.fileStore = fileStore
        self.repository = repository ?? UserDefaultsChallengeRepository(fileStore: fileStore)
        self.roomSync = roomSync ?? RoomSyncService(fileStore: fileStore)
        challenges = self.repository.loadChallenges()
        customTemplates = self.repository.loadTemplates()
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

    func addCustomTemplate(_ template: ChallengeTemplate) {
        customTemplates.append(template)
    }

    func deleteCustomTemplate(_ template: ChallengeTemplate) {
        customTemplates.removeAll { $0.id == template.id }
    }

    func updateCustomTemplate(_ template: ChallengeTemplate) {
        guard let index = customTemplates.firstIndex(where: { $0.id == template.id }) else {
            return
        }
        customTemplates[index] = template
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
            templateName: templateName,
            momentTitles: momentTitles
        )
        challenges.insert(challenge, at: 0)
        return challenge
    }

    /// The first-run story: an immediately filmable personal day. Keeping this
    /// alongside `create` means it has the exact same persistence and reminder
    /// behavior as a story made in the composer.
    @discardableResult
    func createQuickStart() -> Challenge {
        create(
            title: Strings.quickStartTitle,
            mode: .oneDay,
            clipLength: .tiny,
            orientation: .portrait,
            momentTitles: ["morning_light", "on_the_move", "golden_hour"])
    }

    // MARK: - Shared rooms (CloudKit)

    enum RoomError: LocalizedError {
        case notSignedIn
        var errorDescription: String? { Strings.errorSignInFirst }
    }

    /// Create a CloudKit-backed room and mirror it locally.
    @MainActor
    @discardableResult
    func createSharedRoom(
        title: String,
        mode: Challenge.Mode = .sevenDay,
        clipLength: Challenge.ClipLength = .tiny,
        orientation: Challenge.Orientation = .portrait,
        templateName: String? = nil,
        momentTitles: [String]? = nil
    ) async throws -> Challenge {
        guard let me = account?.account else { throw RoomError.notSignedIn }
        let room = try await CloudKitService.createRoom(
            title: title, ownerID: me.id, ownerName: me.displayName,
            mode: mode, clipLength: clipLength, orientation: orientation,
            templateName: templateName, momentTitles: momentTitles)
        let challenge = Challenge(
            id: UUID(), title: room.title, startDate: room.startDate,
            cards: (1...cardCount(for: room.momentTitles)).map { DayCard(day: $0) },
            mode: room.mode, clipLength: room.clipLength,
            orientation: room.orientation,
            templateName: room.templateName,
            momentTitles: room.momentTitles,
            roomCode: room.code, ownerName: room.ownerName, ownerID: room.ownerID)
        challenges.insert(challenge, at: 0)
        return challenge
    }

    /// Join an existing room by its code, mirroring it locally.
    @MainActor
    @discardableResult
    func joinRoom(code: String) async throws -> Challenge {
        guard account?.account != nil else { throw RoomError.notSignedIn }
        let normalized = code.uppercased().trimmingCharacters(in: .whitespaces)
        // Already joined? Jump to it.
        if let existing = challenges.first(where: { $0.roomCode == normalized }) {
            return existing
        }
        let room = try await CloudKitService.fetchRoom(code: normalized)
        let challenge = Challenge(
            id: UUID(), title: room.title, startDate: room.startDate,
            cards: (1...cardCount(for: room.momentTitles)).map { DayCard(day: $0) },
            mode: room.mode, clipLength: room.clipLength,
            orientation: room.orientation,
            templateName: room.templateName,
            momentTitles: room.momentTitles,
            roomCode: room.code, ownerName: room.ownerName, ownerID: room.ownerID)
        challenges.insert(challenge, at: 0)
        await syncRoom(challenge.id)
        return challenge
    }

    /// Pull every member's clips for a room into the local cache, then fold
    /// remote reactions/comments into the local cards.
    @MainActor
    func syncRoom(_ id: UUID) async {
        guard let challenge = challenge(id), let code = challenge.roomCode else { return }
        #if DEBUG
        // Nothing to fetch: this room only ever existed on this device. Its
        // contents come back off disk instead, which is also what makes it
        // survive a relaunch.
        if DemoRoom.isDemo(code) {
            DemoRoom.restore(into: self)
            return
        }
        #endif
        _ = await roomSync.syncClips(code: code)
        if let interactions = await roomSync.fetchInteractions(code: code) {
            roomSync.remoteReactions[code] = interactions.reactions
            roomSync.remoteComments[code] = interactions.comments
            mergeInteractions(interactions, into: id)
        }
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

    // MARK: - Account deletion

    /// Removes the person from the app entirely: their clips and interactions
    /// in every shared room they're part of, then every local story, clip file
    /// and preference on this device.
    ///
    /// Required by App Store guideline 5.1.1(v) — an app that creates accounts
    /// has to let you delete one. Signing out is not the same thing.
    @MainActor
    func deleteAccountAndAllData() async {
        if let me = account?.account {
            // Everything this person authored, addressed by reconstructable
            // record IDs rather than a query. See `deleteMyRoomData`.
            var clips: [(code: String, day: Int)] = []
            var reactions: [(code: String, targetAuthorID: String, day: Int, emoji: String)] = []
            var commentIDs: [String] = []
            var roomCodes: [String] = []

            for challenge in challenges {
                guard let code = challenge.roomCode else { continue }
                roomCodes.append(code)
                for card in challenge.cards {
                    clips.append((code, card.day))
                }
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
                roomCodes: roomCodes)
        }

        // Local wipe happens whether or not the cloud step succeeded — the
        // person asked to be gone from this device, and a network failure
        // must not leave them still signed in with their stories intact.
        for challenge in challenges {
            fileStore.deleteClips(challengeID: challenge.id)
            if let code = challenge.roomCode { roomSync.clearRoom(code) }
        }
        challenges = []
        customTemplates = []
        account?.signOut()
        NotificationPreferences.resetAll()
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
    func saveClip(
        from tempURL: URL,
        day: Int,
        challengeID: UUID,
        overlayText: String? = nil
    ) {
        guard let ci = challenges.firstIndex(where: { $0.id == challengeID }) else { return }
        guard let fileName = fileStore.storeClip(from: tempURL, day: day, challengeID: challengeID) else { return }
        guard let idx = challenges[ci].cards.firstIndex(where: { $0.day == day }) else { return }
        challenges[ci].cards[idx].clipFileName = fileName
        challenges[ci].cards[idx].recordedAt = .now
        challenges[ci].cards[idx].overlayText = overlayText

        // Shared room: also push this clip to CloudKit for friends to see.
        if let code = challenges[ci].roomCode, let me = account?.account {
            let dest = fileStore.clipURL(fileName: fileName, challengeID: challengeID)
            #if DEBUG
            if DemoRoom.isDemo(code) {
                // Stands in for the upload coming back down. Without it your
                // own clip disappears the moment you film it, because a room
                // with remote clips shows only those.
                Task { @MainActor in
                    DemoRoom.absorb(clipAt: dest, day: day, authorID: me.id, into: self)
                }
                return
            }
            #endif
            Task { @MainActor in
                if await roomSync.uploadClip(
                    code: code, day: day, authorID: me.id,
                    authorName: me.displayName, fileURL: dest,
                    overlayText: overlayText
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

    /// Edit a clip's center caption after the fact (from the preview). Local
    /// only for now — room sync of caption edits rides the next clip upload.
    func updateOverlayText(_ text: String?, day: Int, challengeID: UUID) {
        guard let ci = challenges.firstIndex(where: { $0.id == challengeID }),
              let idx = challenges[ci].cards.firstIndex(where: { $0.day == day })
        else { return }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        challenges[ci].cards[idx].overlayText = trimmed?.isEmpty == true ? nil : trimmed
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
    /// room this merges every member's clips (falling back to my local clips
    /// if the room hasn't been synced yet).
    func recordedClips(for challengeID: UUID) -> [DayClip] {
        guard let challenge = challenge(challengeID) else { return [] }
        let presenter = ChallengePresenter(challenge: challenge)
        if let code = challenge.roomCode,
           let remote = roomSync.remoteClips[code], !remote.isEmpty {
            let remoteReactions = roomSync.remoteReactions[code] ?? []
            let remoteComments = roomSync.remoteComments[code] ?? []
            return remote
                .sorted { ($0.day, $0.authorName) < ($1.day, $1.authorName) }
                .map { clip in
                    let isMe = clip.authorID == (account?.account?.id ?? "")
                    let card = isMe ? challenge.cards.first { c in c.day == clip.day } : nil
                    
                    let emojis = isMe 
                        ? (card?.reactions.map(\.emoji) ?? [])
                        : remoteReactions.filter { $0.day == clip.day && $0.targetAuthorID == clip.authorID }.map(\.emoji)
                        
                    let commentLines = isMe
                        ? (card.map(Self.commentLines(for:)) ?? [])
                        : remoteComments
                            .filter { $0.day == clip.day && $0.targetAuthorID == clip.authorID }
                            .sorted { $0.createdAt < $1.createdAt }
                            .map { "\($0.authorName): \($0.text)" }

                    return DayClip(
                        day: clip.day, url: clip.localURL, authorName: clip.authorName,
                        authorID: clip.authorID,
                        label: challenge.isTimeOnly ? nil : presenter.title(forSlot: clip.day),
                        overlayText: clip.overlayText,
                        recordedAt: clip.recordedAt,
                        emoji: emojis,
                        comments: commentLines,
                        key: clip.id)
                }
        }
        return challenge.cards.compactMap { card in
            clipURL(for: card, in: challengeID).map {
                DayClip(
                    day: card.day,
                    url: $0,
                    authorID: account?.account?.id ?? "local",
                    label: challenge.isTimeOnly ? nil : presenter.title(forSlot: card.day),
                    overlayText: card.overlayText,
                    recordedAt: card.recordedAt,
                    emoji: card.reactions.map(\.emoji),
                    comments: Self.commentLines(for: card))
            }
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
