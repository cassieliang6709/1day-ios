#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import Foundation

struct DemoRoomNaming {
    var title: String?
    var moments: [String]
    var members: [String]
    var spreadsDays = false
    var mineFilmedToday = true
    var orientation: Challenge.Orientation = .portrait

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> DemoRoomNaming {
        DemoRoomNaming(
            title: trimmed(defaults.string(forKey: "demoRoomTitle")),
            moments: list(defaults.string(forKey: "demoRoomMoments")),
            members: list(defaults.string(forKey: "demoRoomMembers")),
            spreadsDays: defaults.bool(forKey: "demoRoomSpreadDays"),
            mineFilmedToday: defaults.object(forKey: "demoRoomMineToday") == nil
                ? true
                : defaults.bool(forKey: "demoRoomMineToday"),
            orientation: Challenge.Orientation(
                rawValue: defaults.string(forKey: "demoRoomOrientation") ?? "") ?? .portrait)
    }

    private static func list(_ value: String?) -> [String] {
        (value ?? "").split(separator: ",").compactMap { trimmed(String($0)) }
    }

    func member(_ index: Int) -> String? {
        members.indices.contains(index) ? members[index] : nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

struct DemoRoomStaging {
    var clipFolder: String?
    var showsChrome: Bool

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> DemoRoomStaging {
        let folder = defaults.string(forKey: "demoRoomClips")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DemoRoomStaging(
            clipFolder: (folder?.isEmpty ?? true) ? nil : folder,
            showsChrome: defaults.object(forKey: "demoRoomChrome") == nil
                ? true
                : defaults.bool(forKey: "demoRoomChrome"))
    }

    func clipURLs() -> [URL] {
        guard let clipFolder,
              let documents = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask).first
        else { return [] }
        let directory = documents.appendingPathComponent(clipFolder, isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                    == .orderedAscending
            }
    }
}

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
        store = ChallengeStore(repository: storage, fileStore: storage,
                               roomSync: sync, effects: .isolated)
        store.account = account
        store.challenges = [challenge]
        let draftStorage = LocalRoomDraftStorage(files: storage)
        drafts = ClipDraftStore(repository: draftStorage, fileStore: draftStorage)
    }

    enum Failure: Error { case invalidMemberCount, media, storage }

    static func make(memberCount: Int, chinese: Bool,
                     clipSeconds: Double = DemoClipFactory.standInSeconds
    ) async throws -> LocalRoomRuntime {
        guard (2...3).contains(memberCount) else { throw Failure.invalidMemberCount }
        let naming = DemoRoomNaming.fromLaunchArguments()
        let storage = try LocalRoomDemoStorage()
        let chat = RoomChatDemoTransport(chinese: chinese)
        do {
            let id = UUID()
            let moments = naming.moments.isEmpty
                ? [chinese ? "一起出发" : "Heading out together"]
                : naming.moments
            let staged = DemoRoomStaging.fromLaunchArguments().clipURLs()
            var remote: [CloudKitService.RemoteClip] = []
            var cards: [DayCard] = []
            for (slot, _) in moments.enumerated() {
                let day = slot + 1
                var ownFile: String?
                var ownFilmed: Date?
                for index in 0..<memberCount {
                    try Task.checkCancellation()
                    let daysBack = moments.count - 1 - slot
                    let filmed = naming.spreadsDays
                        ? Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
                            .addingTimeInterval(-Double(index * 7) * 60)
                        : Date().addingTimeInterval(-Double(daysBack * 95 + index * 7) * 60)
                    if index == 0, !naming.mineFilmedToday, Calendar.current.isDateInToday(filmed) {
                        continue
                    }
                    let authorID = index == 0 ? chat.scope.accountID : "demo-friend-\(index)"
                    let name = naming.member(index)
                        ?? (chinese ? "示例成员 \(index + 1)" : "Sample member \(index + 1)")
                    let position = slot * memberCount + index
                    var generated: URL?
                    defer { if let generated { try? FileManager.default.removeItem(at: generated) } }
                    let source: URL
                    if staged.indices.contains(position) {
                        source = staged[position]
                    } else {
                        guard let made = await DemoClipFactory.makeClip(moment: day,
                            label: chinese ? "本地动态示例" : "Local motion sample", author: name,
                            seconds: clipSeconds, orientation: naming.orientation) else { throw Failure.media }
                        generated = made
                        source = made
                    }
                    try Task.checkCancellation()
                    guard let file = storage.storeClip(from: source, day: day, challengeID: id)
                    else { throw Failure.storage }
                    if index == 0 { ownFile = file }
                    if index == 0 { ownFilmed = filmed }
                    remote.append(.init(id: "\(id)-\(authorID)-day\(day)", day: day, authorID: authorID,
                                        authorName: name, recordedAt: filmed,
                                        localURL: storage.clipURL(fileName: file, challengeID: id), overlayText: nil))
                }
                cards.append(DayCard(day: day, clipFileName: ownFile, recordedAt: ownFilmed))
            }
            let challenge = Challenge(id: id,
                title: naming.title ?? (chinese ? "本地房间示例" : "Local room sample"),
                startDate: Date(), cards: cards,
                mode: .oneDay, clipLength: .tiny, orientation: naming.orientation,
                momentTitles: moments,
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

    func replaceClip(authorID: String, day: Int? = nil, from input: URL,
                     prepare: (URL) async throws -> URL = LocalRoomClipImporter.trim) async throws {
        guard !isClosed, !importing,
              let old = store.recordedClips(for: challengeID).first(where: {
                  $0.authorID == authorID && (day == nil || $0.day == day)
              }) else {
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

    func ownDerivedMedia(_ url: URL) {
        if isClosed { try? FileManager.default.removeItem(at: url) }
        else { derivedMedia.insert(url) }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        chat.close()
        source.close()
        store.roomSync.clearRoom(chat.scope.roomCode)
        store.challenges = []
        account.signOut()
        for url in derivedMedia { try? FileManager.default.removeItem(at: url) }
        derivedMedia = []
        preferences.removePersistentDomain(forName: preferencesName)
        storage.close()
    }
}
#endif
