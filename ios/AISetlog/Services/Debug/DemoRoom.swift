#if DEBUG
import Foundation

/// A shared room with friends already in it, made entirely on this device.
///
/// Seeing the multi-person experience currently costs: an iCloud account on
/// the simulator, a second device with a second account, a deployed CloudKit
/// schema, and both people filming at the same time. That's a high price for
/// the answer to "does this screen look right", and while it goes unpaid the
/// shared timeline is the one part of the app nobody ever looks at.
///
/// So this seeds one locally — two friends, their clips, their reactions, a
/// comment. Clips you film in it are absorbed the way a real upload would come
/// back down, which means the filming experience is the real one rather than a
/// screenshot of it.
///
/// The room's contents live on disk, in the same cache a real room downloads
/// into, and are rebuilt from there whenever sync would have run. The
/// in-memory clip cache doesn't survive a relaunch, and a demo room that
/// empties itself overnight would teach the wrong lesson about the design.
///
/// Debug builds only. It is a lens on the design, not a fixture: no test
/// depends on it, and it can be deleted the day two-device testing is cheap.
enum DemoRoom {
    /// Six characters, like a real invite code, so nothing downstream has to
    /// special-case its shape — only its identity.
    static let code = "DEMO01"

    static func isDemo(_ roomCode: String?) -> Bool { roomCode == code }

    private static var inChinese: Bool { AppLanguage.effective.resolved == .chinese }

    private static var title: String { inChinese ? "示例房间" : "Demo room" }

    /// Two friends, because one is a conversation and three is a crowd — the
    /// interesting layout question is what a slot with more takes than room
    /// does with them.
    private static var friendA: (id: String, name: String) {
        ("demo-friend-a", inChinese ? "林安" : "Ana")
    }

    private static var friendB: (id: String, name: String) {
        ("demo-friend-b", inChinese ? "周迟" : "Milo")
    }

    private static let moments = [
        "morning_light", "coffee", "on_the_move", "golden_hour", "wind_down",
    ]

    /// A day part-way through, which is the state the screen actually spends
    /// its time in: some moments doubled up, some waiting, some untouched. A
    /// full room and an empty one are both the easy cases.
    private static var script: [(day: Int, author: (id: String, name: String), minutesAgo: Int)] {
        [
            (1, friendA, 260),
            (2, friendB, 180),
            (2, friendA, 174),
            (3, friendA, 40),
        ]
    }

    // MARK: - Building it

    /// Creates the room and its contents, replacing any previous one.
    ///
    /// - Returns: the challenge to navigate to, or `nil` if the sample video
    ///   isn't in the bundle — there's no demo worth showing without it.
    @MainActor
    @discardableResult
    static func seed(into store: ChallengeStore) -> Challenge? {
        guard let sample = Bundle.main.url(forResource: "sample-film", withExtension: "mp4")
        else { return nil }

        store.challenges.removeAll { isDemo($0.roomCode) }
        store.roomSync.clearRoom(code)

        let cache = store.roomSync.remoteCacheDir(for: code)
        for take in script {
            write(sample, day: take.day, authorID: take.author.id,
                  minutesAgo: take.minutesAgo, into: cache)
        }

        let challenge = Challenge(
            id: UUID(),
            title: title,
            startDate: .now,
            cards: (1...moments.count).map { DayCard(day: $0) },
            mode: .oneDay,
            clipLength: .tiny,
            orientation: .portrait,
            templateName: nil,
            momentTitles: moments,
            roomCode: code,
            ownerName: friendA.name,
            ownerID: friendA.id)

        store.challenges.insert(challenge, at: 0)
        restore(into: store)
        return challenge
    }

    /// Rebuilds the in-memory room from the files on disk. Cheap, idempotent,
    /// and safe to call wherever a real room would have synced.
    @MainActor
    static func restore(into store: ChallengeStore) {
        let cache = store.roomSync.remoteCacheDir(for: code)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cache, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []

        let me = store.account?.account
        let myID = me?.id ?? "demo-me"
        let names = [
            friendA.id: friendA.name,
            friendB.id: friendB.name,
            myID: me?.displayName ?? (inChinese ? "我" : "Me"),
        ]

        let clips = files
            .compactMap { file -> CloudKitService.RemoteClip? in
                guard file.pathExtension == "mp4",
                      let take = parse(file),
                      // A debug tester gets a fresh id every time somebody
                      // taps "use a test identity", so yesterday's clips are
                      // by a stranger. Skipping them beats a roster with a
                      // UUID standing in it.
                      let name = names[take.authorID]
                else { return nil }
                return CloudKitService.RemoteClip(
                    id: file.deletingPathExtension().lastPathComponent,
                    day: take.day,
                    authorID: take.authorID,
                    authorName: name,
                    recordedAt: modified(file),
                    localURL: file,
                    overlayText: nil)
            }
            .sorted { ($0.day, $0.recordedAt) < ($1.day, $1.recordedAt) }

        store.roomSync.stubRoom(
            code: code,
            clips: clips,
            reactions: [
                reaction(day: 1, emoji: "🔥", from: friendB, to: myID, minutesAgo: 240),
                reaction(day: 1, emoji: "😂", from: friendA, to: myID, minutesAgo: 236),
                reaction(day: 2, emoji: "❤️", from: (myID, names[myID] ?? ""),
                         to: friendB.id, minutesAgo: 170),
            ],
            comments: [
                comment(
                    day: 1,
                    text: inChinese ? "这个光也太好了" : "that light though",
                    from: friendB, to: myID, minutesAgo: 235),
            ])
    }

    /// Stands in for an upload coming back down: the clip joins everyone
    /// else's in the room cache, attributed to me.
    @MainActor
    static func absorb(clipAt url: URL, day: Int, authorID: String, into store: ChallengeStore) {
        write(url, day: day, authorID: authorID, minutesAgo: 0,
              into: store.roomSync.remoteCacheDir(for: code))
        restore(into: store)
    }

    // MARK: - Files

    /// `DEMO01_demo-friend-a_day2.mp4` — the author and the moment, recoverable
    /// from the name alone, so disk is enough to rebuild the room from.
    private static func fileName(day: Int, authorID: String) -> String {
        "\(code)_\(authorID)_day\(day).mp4"
    }

    private static func parse(_ file: URL) -> (authorID: String, day: Int)? {
        let stem = file.deletingPathExtension().lastPathComponent
        guard stem.hasPrefix("\(code)_") else { return nil }
        let rest = stem.dropFirst(code.count + 1)
        guard let marker = rest.range(of: "_day", options: .backwards),
              let day = Int(rest[marker.upperBound...])
        else { return nil }
        return (String(rest[..<marker.lowerBound]), day)
    }

    private static func write(
        _ source: URL, day: Int, authorID: String, minutesAgo: Int, into cache: URL
    ) {
        let destination = cache.appendingPathComponent(fileName(day: day, authorID: authorID))
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: source, to: destination)
        // The modification date is the clip's timestamp on the way back in.
        try? FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60)],
            ofItemAtPath: destination.path)
    }

    private static func modified(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .now
    }

    // MARK: - Interactions

    private static func reaction(
        day: Int, emoji: String, from author: (id: String, name: String),
        to targetAuthorID: String, minutesAgo: Int
    ) -> CloudKitService.RemoteReaction {
        CloudKitService.RemoteReaction(
            day: day, emoji: emoji, authorID: author.id, authorName: author.name,
            targetAuthorID: targetAuthorID,
            createdAt: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60))
    }

    private static func comment(
        day: Int, text: String, from author: (id: String, name: String),
        to targetAuthorID: String, minutesAgo: Int
    ) -> CloudKitService.RemoteComment {
        CloudKitService.RemoteComment(
            id: UUID().uuidString, day: day, text: text,
            authorID: author.id, authorName: author.name,
            targetAuthorID: targetAuthorID,
            createdAt: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60))
    }
}
#endif
