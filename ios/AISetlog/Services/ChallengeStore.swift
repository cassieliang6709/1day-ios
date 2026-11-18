import Foundation
import Observation

@Observable
final class ChallengeStore {
    var challenges: [Challenge] = [] {
        didSet {
            repository.saveChallenges(challenges)
            effects.reconcileReminders(challenges)
            let oldRooms = Set(oldValue.compactMap(\.roomCode))
            let newRooms = Set(challenges.compactMap(\.roomCode))
            for code in newRooms.subtracting(oldRooms) {
                roomSync.restoreCachedContent(code: code)
            }
            if oldRooms != newRooms {
                effects.reconcileSubscriptions(challenges)
            }
        }
    }

    var account: AccountStore?
    var myRoomProfile: @MainActor () -> MyRoomProfile? = { nil }
    var adoptAvatar: @MainActor (URL) -> Void = { _ in }
    var forgetAvatar: @MainActor () -> Void = {}

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
        for code in Set(challenges.compactMap(\.roomCode)) {
            self.roomSync.restoreCachedContent(code: code)
        }
    }

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


    enum RoomError: LocalizedError {
        case notSignedIn
        var errorDescription: String? { Strings.errorSignInFirst }
    }

    enum IsolationError: Error { case cloudRoomManagementDisabled }

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
        await roomSync.recordMembership(
            code: room.code, authorID: me.id, displayName: me.displayName)
        await publishMyProfile(toRoom: room.code)
        return challenge
    }

    static let ownerMemberRecordsSince = DateComponents(
        calendar: .init(identifier: .gregorian), timeZone: .init(identifier: "Asia/Shanghai"),
        year: 2026, month: 10, day: 28).date!

    @ObservationIgnored private var roomRestoration: (userID: String, revision: UInt64, request: UUID)?

    static let roomsAccountKey = "rooms.accountID.v1"

    @MainActor
    func reconcileAccountRooms(defaults: UserDefaults = .standard) async {
        roomSync.reconcileCacheAccount()
        guard let me = account?.account else {
            Log.sync.notice("reconcileAccountRooms skipped: no account")
            return
        }
        Log.sync.info("reconcileAccountRooms start")
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
        if me.name == nil, let name = mine.displayName { account?.rename(to: name) }
        if myRoomProfile()?.avatarURL == nil, let avatar = mine.avatarFile { adoptAvatar(avatar) }

        let have = Set(challenges.compactMap(\.roomCode))
        var rooms: [CloudKitService.RemoteRoom] = mine.owned.filter {
            !have.contains($0.code)
                && (mine.memberCodes.contains($0.code) || $0.startDate < Self.ownerMemberRecordsSince)
        }
        let ownedCodes = Set(rooms.map(\.code))
        for code in Set(mine.memberCodes) where !have.contains(code) && !ownedCodes.contains(code) {
            if let room = try? await roomSync.fetchRoom(code: code) { rooms.append(room) }
            guard isCurrentAccount(me.id, revision: revision), roomRestoration?.request == request,
                  !Task.isCancelled else { return }
        }
        guard !rooms.isEmpty else { return }
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

    @MainActor
    @discardableResult
    func joinRoom(code: String) async throws -> Challenge {
        guard effects.allowsCloudRoomManagement else { throw IsolationError.cloudRoomManagementDisabled }
        guard let me = account?.account else { throw RoomError.notSignedIn }
        let revision = AccountStore.identityRevision
        try Task.checkCancellation()
        let normalized = InviteCode.normalize(code)
        if let existing = challenges.first(where: { $0.roomCode == normalized }) {
            return existing
        }
        guard InviteCode.isValid(normalized) else {
            throw CloudKitService.CKServiceError.roomNotFound
        }
        let room = try await roomSync.fetchRoom(code: normalized)
        try Task.checkCancellation()
        guard isCurrentAccount(me.id, revision: revision) else { throw CancellationError() }
        let people = await roomSync.peopleInRoom(code: normalized, ownerID: room.ownerID)
        try Task.checkCancellation()
        guard isCurrentAccount(me.id, revision: revision) else { throw CancellationError() }
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
        await roomSync.recordMembership(
            code: room.code, authorID: me.id, displayName: me.displayName)
        try Task.checkCancellation()
        guard isCurrentAccount(me.id, revision: revision), self.challenge(challenge.id) != nil
        else { throw CancellationError() }
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentAccount(me.id, revision: revision) else { return }
            self.roomSync.forgetPublishedProfile(code: room.code)
            await self.publishMyProfile(toRoom: room.code)
            guard self.isCurrentAccount(me.id, revision: revision) else { return }
            await self.syncRoom(challenge.id)
        }
        return challenge
    }

    @MainActor
    func syncRoom(_ id: UUID) async {
        guard let challenge = challenge(id), let code = challenge.roomCode else { return }
        guard !effects.allowsCloudRoomManagement || account?.isSignedIn == true else {
            Log.sync.notice("syncRoom \(code, privacy: .public) skipped: not signed in")
            return
        }
        let started = Date()
        Log.sync.info("syncRoom \(code, privacy: .public) start")
        defer {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            Log.sync.info("syncRoom \(code, privacy: .public) done \(ms)ms")
        }
        let userID = account?.account?.id
        let revision = AccountStore.identityRevision
        let isCurrent = {
            self.isCurrentAccount(userID, revision: revision)
                && self.challenge(id)?.roomCode == code && !Task.isCancelled
        }
        roomSync.restoreCachedContent(code: code)
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
        if let interactions = await roomSync.fetchInteractions(code: code) {
            guard isCurrent() else { return }
            let kept = keepingMyRecentInteractions(interactions, code: code)
            roomSync.remoteReactions[code] = kept.reactions
            roomSync.remoteComments[code] = kept.comments
            mergeInteractions(interactions, into: id)
        }
        guard isCurrent() else { return }
        await syncRoomTitle(id, code: code)
    }

    private func isCurrentAccount(_ userID: String?, revision: UInt64) -> Bool {
        account?.account?.id == userID && AccountStore.identityRevision == revision
    }

    static let myInteractionGrace = RoomContentCache.confirmationGrace

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

    @MainActor
    private func uploadMissingClips(
        in challenge: Challenge, code: String, remote: [CloudKitService.RemoteClip]
    ) async -> Bool {
        guard effects.allowsCloudRoomManagement, let me = account?.account else { return false }
        let revision = AccountStore.identityRevision
        let roomCopies = Dictionary(
            remote.filter { $0.authorID == me.id }
                .map { (Self.takeKey(day: $0.day, takeID: takeID(of: $0, code: code)), $0.recordedAt) },
            uniquingKeysWith: max)
        var uploadedAny = false
        for card in challenge.cards {
            guard isCurrentAccount(me.id, revision: revision),
                  self.challenge(challenge.id)?.roomCode == code, !Task.isCancelled else { return uploadedAny }
            guard let fileName = card.clipFileName else { continue }
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
            if let roomCopy = roomCopies[Self.takeKey(day: card.day, takeID: nil)], roomCopy >= (card.recordedAt ?? .distantPast) {
                continue
            }
            let file = fileStore.clipURL(fileName: fileName, challengeID: challenge.id)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            if await roomSync.uploadClip(
                code: code, day: card.day, authorID: me.id,
                authorName: me.displayName, fileURL: file,
                captions: card.captions,
                recordedAt: card.recordedAt ?? .now
            ) {
                uploadedAny = true
            }
        }
        return uploadedAny
    }

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

    @MainActor
    func syncSharedRooms() async {
        let ids = challenges.filter(\.isShared).map(\.id)
        Log.sync.info("syncSharedRooms \(ids.count) rooms")
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

    static let sharedRoomSyncWidth = 3

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

    func todaysPlan(now: Date = .now, calendar: Calendar = .current) -> Challenge? {
        plan(on: now, calendar: calendar)
    }

    func plan(on day: Date, calendar: Calendar = .current) -> Challenge? {
        let now = day
        return challenges.first {
            !$0.isShared && !$0.isTimeOnly && $0.momentTitles?.isEmpty == false
                && calendar.isDate($0.startDate, inSameDayAs: now)
        }
    }

    static let roomCapacity = 6

    func members(for challengeID: UUID) -> [(id: String, name: String)] {
        guard let challenge = challenge(challengeID), let code = challenge.roomCode else { return [] }
        var seen: [String: String] = [:]
        if let ownerName = challenge.ownerName {
            seen[challenge.ownerID ?? ownerName] = ownerName
        }
        for member in (roomSync.remoteMembers[code] ?? [:]).values
        where !member.displayName.isEmpty || seen[member.userID] == nil {
            seen[member.userID] = member.displayName
        }
        for clip in roomSync.remoteClips[code] ?? [] where !clip.authorName.isEmpty || seen[clip.authorID] == nil {
            seen[clip.authorID] = clip.authorName
        }
        if let me = account?.account { seen[me.id] = me.displayName }
        if challenge.ownerID == nil, let ownerName = challenge.ownerName,
           seen.contains(where: { $0.key != ownerName && $0.value == ownerName }) {
            seen.removeValue(forKey: ownerName)
        }
        return seen.map { (id: $0.key, name: $0.value) }.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
    }

    func signOut() {
        for challenge in challenges {
            if let code = challenge.roomCode { roomSync.clearRoom(code) }
        }
        account?.signOut()
    }


    @MainActor
    func deleteAccountAndAllData() async {
        guard effects.allowsCloudRoomManagement else { return }
        if let me = account?.account {
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
            if effects.allowsCloudRoomManagement, let me = account?.account {
                let sync = roomSync
                Task { @MainActor in await sync.leaveRemotely(code: code, authorID: me.id) }
            }
            roomSync.clearRoom(code)
        }
        challenges.removeAll { $0.id == id }
    }

    func saveClip(
        from tempURL: URL,
        day: Int,
        challengeID: UUID,
        overlayText: String? = nil,
        captions: [Caption]? = nil,
        recordedAt: Date = .now,
        take: TakeTarget = .replace(nil)
    ) {
        let captions = (captions ?? .single(overlayText)).drawable
        guard let ci = challenges.firstIndex(where: { $0.id == challengeID }) else { return }
        guard let idx = challenges[ci].cards.firstIndex(where: { $0.day == day }) else { return }

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
            let id = card.moreTakes[t].id
            guard let stored = fileStore.storeExtraTake(
                from: tempURL, day: day, takeID: id, challengeID: challengeID) else { return }
            fileName = stored
            takeID = id
            challenges[ci].cards[idx].moreTakes[t].fileName = stored
            challenges[ci].cards[idx].moreTakes[t].recordedAt = recordedAt
            challenges[ci].cards[idx].moreTakes[t].captions = captions
        } else {
            let id = UUID()
            guard let stored = fileStore.storeExtraTake(
                from: tempURL, day: day, takeID: id, challengeID: challengeID) else { return }
            fileName = stored
            takeID = id
            challenges[ci].cards[idx].moreTakes.append(ClipTake(
                id: id, fileName: stored, recordedAt: recordedAt,
                captions: captions))
        }

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
            if words == nil { challenges[ci].cards[idx].captionSticker = nil }
        }
        pushCaptionsToRoom(day: day, takeID: takeID, challengeIndex: ci)
    }

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


    var currentAuthor: (id: String, name: String) {
        if let me = account?.account { return (me.id, me.displayName) }
        return ("local", "You")
    }

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


    func hasPokedToday(challengeID: UUID, targetAuthorID: String) -> Bool {
        guard let code = challenge(challengeID)?.roomCode else { return false }
        return PokeLimiter().hasPoked(code: code, targetAuthorID: targetAuthorID)
    }

    @discardableResult
    func poke(challengeID: UUID, targetAuthorID: String) -> Bool {
        guard let code = challenge(challengeID)?.roomCode,
              let acct = account?.account, targetAuthorID != acct.id,
              PokeLimiter().claim(code: code, targetAuthorID: targetAuthorID)
        else { return false }
        Task { @MainActor in
            if await !roomSync.sendPoke(
                code: code, authorID: acct.id, authorName: acct.displayName,
                targetAuthorID: targetAuthorID) {
                PokeLimiter().release(code: code, targetAuthorID: targetAuthorID)
            }
        }
        return true
    }

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

        if let code = challenge(challengeID)?.roomCode, account?.account != nil {
            Task { @MainActor in
                await roomSync.deleteComment(id: commentID.uuidString, code: code)
            }
        }
    }

    func recordedClips(for challengeID: UUID) -> [DayClip] {
        guard let challenge = challenge(challengeID) else { return [] }
        let presenter = ChallengePresenter(challenge: challenge)
        if let code = challenge.roomCode,
           let remote = roomSync.remoteClips[code], !remote.isEmpty {
            let remoteReactions = roomSync.remoteReactions[code] ?? []
            let remoteComments = roomSync.remoteComments[code] ?? []
            let myID = account?.account?.id
            let uploaded = Set(remote.filter { $0.authorID == myID }
                .map { Self.takeKey(day: $0.day, takeID: takeID(of: $0, code: code)) })
            let pending = localClips(in: challenge, presenter: presenter)
                .filter { !uploaded.contains(Self.takeKey(day: $0.day, takeID: $0.takeID)) }
            return (remote
                .map { clip in
                    let isMe = clip.authorID == (account?.account?.id ?? "")
                    let card = isMe ? challenge.cards.first { c in c.day == clip.day } : nil
                    let take = takeID(of: clip, code: code)
                    let carriesInteractions = take == nil
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
                .sorted {
                    ($0.day, $0.authorName ?? "", $0.takeID == nil ? 0 : 1, $0.recordedAt ?? .distantPast)
                        < ($1.day, $1.authorName ?? "", $1.takeID == nil ? 0 : 1, $1.recordedAt ?? .distantPast)
                }
        }
        return localClips(in: challenge, presenter: presenter)
    }

    private func takeID(of clip: CloudKitService.RemoteClip, code: String) -> UUID? {
        CloudKitService.takeID(
            fromClipRecordName: clip.id, code: code, authorID: clip.authorID, day: clip.day)
    }

    private static func takeKey(day: Int, takeID: UUID?) -> String {
        "\(day)#\(takeID?.uuidString ?? "1")"
    }

    private func localClips(
        in challenge: Challenge, presenter: ChallengePresenter
    ) -> [DayClip] {
        challenge.cards.flatMap { card -> [DayClip] in
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

    private static func commentLines(for card: DayCard) -> [String] {
        card.comments
            .sorted { $0.createdAt < $1.createdAt }
            .map { "\($0.authorName): \($0.text)" }
    }

    private func cardCount(for momentTitles: [String]?) -> Int {
        guard let count = momentTitles?.count, count > 0 else { return 7 }
        return count
    }
}
