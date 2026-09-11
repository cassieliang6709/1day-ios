#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import Foundation

/// Data/runtime owner for reusing the real room UI. Not yet an entry point:
/// views must also use its chat transport, drafts and preferences before exposure.
@MainActor
final class LocalRoomRuntime {
    let storage: LocalRoomDemoStorage
    let account: AccountStore
    let store: ChallengeStore
    let drafts: ClipDraftStore
    let chat: RoomChatDemoTransport
    let challengeID: UUID
    let preferences: UserDefaults
    private let preferencesName: String
    private let source: LocalRoomSyncSource
    private(set) var isClosed = false
    private var derivedMedia: Set<URL> = []
    private var importing = false

    private init(storage: LocalRoomDemoStorage, source: LocalRoomSyncSource,
                 chat: RoomChatDemoTransport, challenge: Challenge) throws {
        let name = "1day.local-room.preferences.\(UUID())"
        guard let preferences = UserDefaults(suiteName: name) else { throw Failure.storage }
        self.preferencesName = name
        self.preferences = preferences
        self.storage = storage
        self.source = source
        self.chat = chat
        self.challengeID = challenge.id
        account = AccountStore(localIdentity: .init(id: chat.scope.accountID, displayName: challenge.ownerName ?? "Sample"))
        let sync = RoomSyncService(fileStore: storage, transport: source.transport)
        store = ChallengeStore(repository: storage, fileStore: storage, coverStore: storage,
                               roomSync: sync, effects: .isolated)
        store.account = account
        store.challenges = [challenge]
        let draftStorage = LocalRoomDraftStorage(files: storage)
        drafts = ClipDraftStore(repository: draftStorage, fileStore: draftStorage)
    }

    enum Failure: Error { case invalidMemberCount, media, storage }

    /// Generates app-owned moving fixtures and feeds the production store model.
    /// Each member has a stable unique clip key; only temporary generated files
    /// are removed. No photos, real account data or real room records are read.
    static func make(memberCount: Int, chinese: Bool) async throws -> LocalRoomRuntime {
        guard (2...3).contains(memberCount) else { throw Failure.invalidMemberCount }
        let storage = try LocalRoomDemoStorage()
        let chat = RoomChatDemoTransport(chinese: chinese)
        do {
            let id = UUID()
            var remote: [CloudKitService.RemoteClip] = []
            var ownFile: String?
            for index in 0..<memberCount {
                try Task.checkCancellation()
                let authorID = index == 0 ? chat.scope.accountID : "demo-friend-\(index)"
                let name = chinese ? "示例成员 \(index + 1)" : "Sample member \(index + 1)"
                guard let generated = await DemoClipFactory.makeClip(moment: 1,
                    label: chinese ? "本地动态示例" : "Local motion sample", author: name,
                    seconds: 3, orientation: .portrait) else { throw Failure.media }
                defer { try? FileManager.default.removeItem(at: generated) }
                try Task.checkCancellation()
                guard let file = storage.storeClip(from: generated, day: 1, challengeID: id) else { throw Failure.storage }
                if index == 0 { ownFile = file }
                remote.append(.init(id: "\(id)-\(authorID)-day1", day: 1, authorID: authorID,
                                    authorName: name, recordedAt: Date(),
                                    localURL: storage.clipURL(fileName: file, challengeID: id), overlayText: nil))
            }
            let challenge = Challenge(id: id, title: chinese ? "本地房间示例" : "Local room sample",
                startDate: Date(), cards: [DayCard(day: 1, clipFileName: ownFile, recordedAt: Date())],
                mode: .oneDay, clipLength: .tiny, orientation: .portrait,
                momentTitles: [chinese ? "一起出发" : "Heading out together"],
                roomCode: chat.scope.roomCode, ownerName: remote.first?.authorName, ownerID: chat.scope.accountID)
            let source = LocalRoomSyncSource(code: chat.scope.roomCode, clips: remote)
            let runtime = try LocalRoomRuntime(storage: storage, source: source, chat: chat, challenge: challenge)
            await runtime.store.syncRoom(id)
            if Task.isCancelled { runtime.close(); throw CancellationError() }
            return runtime
        } catch {
            chat.close()
            storage.close()
            throw error
        }
    }

    /// Atomically replaces one fixture after preparation. Old files remain leased
    /// until close so a currently displayed production player cannot lose its URL.
    func replaceClip(authorID: String, from input: URL,
                     prepare: (URL) async throws -> URL = LocalRoomClipImporter.trim) async throws {
        guard !isClosed, !importing,
              let old = store.recordedClips(for: challengeID).first(where: { $0.authorID == authorID }) else {
            throw Failure.storage
        }
        importing = true
        defer { importing = false }
        let prepared = try await prepare(input)
        defer { if prepared != input { try? FileManager.default.removeItem(at: prepared) } }
        try Task.checkCancellation()
        guard !isClosed,
              let ci = store.challenges.firstIndex(where: { $0.id == challengeID }),
              let cardIndex = store.challenges[ci].cards.firstIndex(where: { $0.day == old.day }) else {
            throw Failure.storage
        }
        guard let file = storage.storeClip(from: prepared, day: old.day, challengeID: challengeID) else {
            throw Failure.storage
        }
        let url = storage.clipURL(fileName: file, challengeID: challengeID)
        try source.replaceClip(authorID: authorID, day: old.day, url: url)
        if authorID == account.account?.id {
            store.challenges[ci].cards[cardIndex].clipFileName = file
        }
        await store.syncRoom(challengeID)
    }

    /// A render completing after dismissal is discarded rather than resurrecting
    /// a closed session. Call only with newly created compositor outputs.
    func ownDerivedMedia(_ url: URL) {
        if isClosed { try? FileManager.default.removeItem(at: url) }
        else { derivedMedia.insert(url) }
    }

    /// The presenting owner calls this on actual dismissal, not when a child
    /// preview/photo picker temporarily obscures the room.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        chat.close()
        source.close()
        store.roomSync.clearRoom(chat.scope.roomCode)
        store.challenges = []
        store.customTemplates = []
        account.signOut()
        for url in derivedMedia { try? FileManager.default.removeItem(at: url) }
        derivedMedia = []
        preferences.removePersistentDomain(forName: preferencesName)
        storage.close()
    }
}
#endif
