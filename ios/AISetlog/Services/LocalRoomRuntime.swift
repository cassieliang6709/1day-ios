#if DEBUG || LOCAL_ROOM_CHAT_DEMO
import Foundation

/// The names the demo room wears on screen.
///
/// Pointing a screen recorder at this room is the reason it exists — the
/// Simulator has no camera and no second account — and 「示例成员 1」 and
/// 「本地房间示例」 are the wrong words to have on screen while doing it.
///
/// They are also the words two UI tests match on: `LocalRoomImportUITests`
/// looks up `app.buttons["示例成员 2"]` and `LocalFormalMomentUITests` matches
/// 「一起出发」. So the defaults do not move. An override arrives by launch
/// argument, the same way `DemoEntries` arrives, and anything that passes none
/// sees exactly what it saw before:
///
/// ```
/// app.launchArguments = [
///     "-demoEntries", "YES",
///     "-demoRoomTitle", "我们的一天",
///     "-demoRoomMembers", "小蓝,小白",
///     "-demoRoomMoments", "晨光,午饭,傍晚",
/// ]
/// ```
struct DemoRoomNaming {
    var title: String?
    /// Empty means the one default moment. Each entry adds a slot, and every
    /// member gets a clip in every slot — so three names is a six-clip room.
    var moments: [String]
    var members: [String]

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> DemoRoomNaming {
        DemoRoomNaming(
            title: trimmed(defaults.string(forKey: "demoRoomTitle")),
            moments: list(defaults.string(forKey: "demoRoomMoments")),
            members: list(defaults.string(forKey: "demoRoomMembers")))
    }

    private static func list(_ value: String?) -> [String] {
        (value ?? "").split(separator: ",").compactMap { trimmed(String($0)) }
    }

    /// The override for the member in `index`, or `nil` when none was given for
    /// that position. A short list renames only the members it names instead of
    /// blanking the rest, so `"小蓝"` alone is a valid thing to pass.
    func member(_ index: Int) -> String? {
        members.indices.contains(index) ? members[index] : nil
    }

    /// Empty and whitespace-only are the same as absent: a shell that expands a
    /// variable to nothing should leave the defaults standing, not put a blank
    /// name under an avatar.
    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Where the demo room's clips come from, and whether it admits to being one.
///
/// The room underneath is already the production room. What reads as "demo" is
/// the scaffolding above it — the local-only notice, the member picker and the
/// import menu — which is exactly the part a screen recording should not have.
/// Turning it off is only safe because it is paired with `clipFolder`: without
/// somewhere to take clips from, a room with no import menu is a room stuck
/// with generated colour cards.
///
/// ```
/// xcrun simctl launch booted com.cassie.AISetlog --args \
///     -demoEntries YES -demoRoomClips demo-clips -demoRoomChrome NO
/// ```
struct DemoRoomStaging {
    /// A folder under the app's Documents directory. Push files into it with
    /// `xcrun simctl get_app_container booted <bundle> data`.
    var clipFolder: String?
    /// Defaults to on, so nothing that does not ask loses the scaffolding.
    var showsChrome: Bool

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> DemoRoomStaging {
        let folder = defaults.string(forKey: "demoRoomClips")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DemoRoomStaging(
            clipFolder: (folder?.isEmpty ?? true) ? nil : folder,
            // `object(forKey:)` rather than `bool(forKey:)`: an absent key and
            // an explicit NO both read as false, and they mean opposite things.
            showsChrome: defaults.object(forKey: "demoRoomChrome") == nil
                ? true
                : defaults.bool(forKey: "demoRoomChrome"))
    }

    /// The staged clips, sorted by file name, handed out moment-major — file 1
    /// is the first member of the first moment, file 2 the second member of the
    /// same moment, and so on. Naming them `1.mp4`…`6.mp4` is the whole
    /// protocol. Missing or short, the generator fills the rest.
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
    static func make(memberCount: Int, chinese: Bool,
                     clipSeconds: Double = DemoClipFactory.standInSeconds
    ) async throws -> LocalRoomRuntime {
        guard (2...3).contains(memberCount) else { throw Failure.invalidMemberCount }
        let naming = DemoRoomNaming.fromLaunchArguments()
        let storage = try LocalRoomDemoStorage()
        let chat = RoomChatDemoTransport(chinese: chinese)
        do {
            let id = UUID()
            // One slot unless a launch argument names more. `buildFriendsTogether`
            // groups clips by day and plays the groups in sequence, so each extra
            // moment is another segment of the film rather than another cell —
            // which is the difference between a room that demonstrates a day and
            // one that demonstrates a single shot.
            let moments = naming.moments.isEmpty
                ? [chinese ? "一起出发" : "Heading out together"]
                : naming.moments
            let staged = DemoRoomStaging.fromLaunchArguments().clipURLs()
            var remote: [CloudKitService.RemoteClip] = []
            var cards: [DayCard] = []
            for (slot, _) in moments.enumerated() {
                let day = slot + 1
                var ownFile: String?
                for index in 0..<memberCount {
                    try Task.checkCancellation()
                    let authorID = index == 0 ? chat.scope.accountID : "demo-friend-\(index)"
                    let name = naming.member(index)
                        ?? (chinese ? "示例成员 \(index + 1)" : "Sample member \(index + 1)")
                    // A staged file is the caller's, and outlives this room; a
                    // generated one is ours, and does not.
                    let position = slot * memberCount + index
                    var generated: URL?
                    defer { if let generated { try? FileManager.default.removeItem(at: generated) } }
                    let source: URL
                    if staged.indices.contains(position) {
                        source = staged[position]
                    } else {
                        guard let made = await DemoClipFactory.makeClip(moment: day,
                            label: chinese ? "本地动态示例" : "Local motion sample", author: name,
                            seconds: clipSeconds, orientation: .portrait) else { throw Failure.media }
                        generated = made
                        source = made
                    }
                    try Task.checkCancellation()
                    guard let file = storage.storeClip(from: source, day: day, challengeID: id)
                    else { throw Failure.storage }
                    if index == 0 { ownFile = file }
                    remote.append(.init(id: "\(id)-\(authorID)-day\(day)", day: day, authorID: authorID,
                                        authorName: name, recordedAt: Date(),
                                        localURL: storage.clipURL(fileName: file, challengeID: id), overlayText: nil))
                }
                cards.append(DayCard(day: day, clipFileName: ownFile, recordedAt: Date()))
            }
            let challenge = Challenge(id: id,
                title: naming.title ?? (chinese ? "本地房间示例" : "Local room sample"),
                startDate: Date(), cards: cards,
                mode: .oneDay, clipLength: .tiny, orientation: .portrait,
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

    /// Atomically replaces one fixture after preparation. Old files remain leased
    /// until close so a currently displayed production player cannot lose its URL.
    /// `day` picks which of that author's slots to replace. Nil keeps the
    /// original behaviour — their first clip — which is the only clip they have
    /// in a one-moment room, and is what every existing caller means.
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
