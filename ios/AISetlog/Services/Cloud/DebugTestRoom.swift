#if DEBUG
import CloudKit
import Foundation

/// Debug-only: a real shared room, made in one tap, that already has two
/// friends' clips in it.
///
/// Unlike `DebugFakeFriends`, which pastes clips into the local copy and never
/// touches the server, this one writes real `Room` and `Clip` records, so it
/// only runs when the build is signed against CloudKit Development
/// (`CLOUDKIT_ENVIRONMENT` in project.yml) and refuses against Production.
/// The room itself goes through
/// `ChallengeStore.createSharedRoom` exactly as the composer's does; only the
/// friends' clips need their own writer, because `CloudKitService.uploadClip`
/// stamps every clip `recordedAt = now` and the point is to have one from
/// three days ago.
///
/// Settings has the button; `-debugCreateTestRoom YES` runs it once at launch.
@MainActor
enum DebugTestRoom {
    static let launchFlag = "debugCreateTestRoom"
    /// Set by the launch flag; consumed the first time it is read.
    private static var launchConsumed = false

    static func consumeLaunchRequest() -> Bool {
        guard !launchConsumed, UserDefaults.standard.bool(forKey: launchFlag) else { return false }
        launchConsumed = true
        return true
    }

    private struct FakeClip {
        let authorID: String
        let authorName: String
        let day: Int
        let daysAgo: Int
        let caption: String?
    }

    private static let fakeClips = [
        FakeClip(authorID: "debug-friend-xiaohong", authorName: "小红", day: 1, daysAgo: 0, caption: "今天的测试视频"),
        FakeClip(authorID: "debug-friend-xiaoming", authorName: "小明", day: 2, daysAgo: 3, caption: nil),
        FakeClip(authorID: "debug-friend-xiaohong", authorName: "小红", day: 3, daysAgo: 1, caption: nil),
    ]

    struct ProductionDatabaseError: LocalizedError {
        var errorDescription: String? { Strings.debugTestRoomNeedsDevelopment }
    }

    /// Creates the room, uploads the fake clips, syncs. Throws
    /// `ProductionDatabaseError` when the build talks to CloudKit Production,
    /// `ChallengeStore.RoomError.notSignedIn` when nobody is signed in.
    @discardableResult
    static func create(in store: ChallengeStore) async throws -> Challenge {
        guard !CloudKitService.isProduction else { throw ProductionDatabaseError() }
        guard store.account?.account != nil else { throw ChallengeStore.RoomError.notSignedIn }
        let challenge = try await store.createSharedRoom(title: Strings.debugTestRoomTitle)
        guard let code = challenge.roomCode else { return challenge }
        for clip in fakeClips {
            guard let url = await DemoClipFactory.makeClip(
                moment: clip.day, label: "测试视频", author: clip.authorName,
                seconds: DemoClipFactory.standInSeconds,
                orientation: challenge.resolvedOrientation)
            else { continue }
            try await upload(clip, code: code, fileURL: url)
        }
        await store.syncRoom(challenge.id)
        print("[debug-room] created test room code=\(code) with \(fakeClips.count) fake clips")
        return challenge
    }

    /// The same record `CloudKitService.uploadClip` writes — same type, same
    /// deterministic name, same fields — with someone else as the author and
    /// a back-dated `recordedAt`.
    private static func upload(_ clip: FakeClip, code: String, fileURL: URL) async throws {
        let db = CKContainer(identifier: CloudKitService.containerID).publicCloudDatabase
        let id = CKRecord.ID(recordName: CloudKitService.clipRecordName(
            code: code, authorID: clip.authorID, day: clip.day))
        let record = CKRecord(recordType: "Clip", recordID: id)
        let recordedAt = Calendar.current.date(byAdding: .day, value: -clip.daysAgo, to: .now) ?? .now
        record["roomCode"] = code as CKRecordValue
        record["day"] = clip.day as CKRecordValue
        record["authorID"] = clip.authorID as CKRecordValue
        record["authorName"] = clip.authorName as CKRecordValue
        record["recordedAt"] = recordedAt as CKRecordValue
        record["video"] = CKAsset(fileURL: fileURL)
        if let caption = clip.caption { record["overlayText"] = caption as CKRecordValue }
        let (saved, _) = try await db.modifyRecords(
            saving: [record], deleting: [], savePolicy: .allKeys)
        for (_, result) in saved { _ = try result.get() }
    }
}
#endif
