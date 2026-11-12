import XCTest
@testable import AISetlog

/// Which room videos a sync downloads again, and how the room syncs overlap.
///
/// The CloudKit half of `fetchClips` needs a signed-in simulator; the rule that
/// decides what it fetches doesn't, and that rule is where "every sync pulls
/// every video" either stays fixed or comes back.
final class RoomClipCacheTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-clip-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
        super.tearDown()
    }

    private func entry(_ name: String, _ version: String?) -> RoomClipCache.RemoteEntry {
        .init(recordName: name, version: version)
    }

    private func writeFile(_ name: String, _ contents: String) throws {
        try Data(contents.utf8).write(to: dir.appendingPathComponent(name))
    }

    private func contents(of recordName: String) throws -> String {
        let url = RoomClipCache.fileURL(recordName: recordName, in: dir)
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    // MARK: - Plan

    func testPlanDownloadsOnlyNewAndChangedRecordsAndDropsDeparted() {
        let manifest = RoomClipCache.Manifest(versions: [
            "same": "v1", "changed": "v1", "gone": "v1", "lostFile": "v1",
        ])
        let plan = RoomClipCache.plan(
            remote: [
                entry("same", "v1"), entry("changed", "v2"), entry("new", "v1"),
                entry("lostFile", "v1"), entry("unversioned", nil),
            ],
            manifest: manifest,
            cachedFiles: ["same", "changed", "gone", "unversioned"])
        XCTAssertEqual(plan.reuse, ["same"])
        XCTAssertEqual(plan.download, ["changed", "new", "lostFile", "unversioned"])
        XCTAssertEqual(plan.remove, ["gone"])
    }

    func testFirstSyncWithoutManifestDownloadsEverythingOnce() {
        let plan = RoomClipCache.plan(
            remote: [entry("a", "v1"), entry("b", "v1")],
            manifest: .init(), cachedFiles: ["a", "b"])
        XCTAssertEqual(plan.download, ["a", "b"])
        XCTAssertEqual(plan.remove, [])
    }

    func testSecondSyncOfAnUnchangedRoomDownloadsNothing() {
        let remote = [entry("a", "v1"), entry("b", "v1")]
        let first = RoomClipCache.plan(remote: remote, manifest: .init(), cachedFiles: [])
        let manifest = RoomClipCache.manifest(
            after: first, remote: remote, downloaded: ["a", "b"], previous: .init())
        let second = RoomClipCache.plan(remote: remote, manifest: manifest, cachedFiles: ["a", "b"])
        XCTAssertEqual(second.download, [])
        XCTAssertEqual(second.reuse, ["a", "b"])
    }

    // MARK: - Manifest after a sync

    func testFailedDownloadKeepsOldEntrySoTheNextSyncRetries() {
        let previous = RoomClipCache.Manifest(versions: ["kept": "v1", "retry": "v1", "gone": "v1"])
        let remote = [entry("kept", "v1"), entry("retry", "v2"), entry("fresh", "v1"), entry("failedNew", "v1")]
        let plan = RoomClipCache.plan(
            remote: remote, manifest: previous, cachedFiles: ["kept", "retry", "gone"])
        let next = RoomClipCache.manifest(
            after: plan, remote: remote, downloaded: ["fresh"], previous: previous)
        XCTAssertEqual(next.versions, ["kept": "v1", "retry": "v1", "fresh": "v1"])

        let again = RoomClipCache.plan(
            remote: remote, manifest: next, cachedFiles: ["kept", "retry", "fresh"])
        XCTAssertEqual(again.download, ["retry", "failedNew"])
        XCTAssertEqual(again.reuse, ["kept", "fresh"])
    }

    // MARK: - Video version

    func testCaptionEditDoesNotChangeTheVideoVersion() {
        let take = Date(timeIntervalSince1970: 1_700_000_123.456)
        XCTAssertEqual(
            RoomClipCache.videoVersion(recordedAt: take, changeTag: "tag-before-caption"),
            RoomClipCache.videoVersion(recordedAt: take, changeTag: "tag-after-caption"))
        XCTAssertNotEqual(
            RoomClipCache.videoVersion(recordedAt: take, changeTag: "x"),
            RoomClipCache.videoVersion(recordedAt: take.addingTimeInterval(1), changeTag: "x"))
    }

    func testVersionFallsBackToChangeTagThenNothing() {
        XCTAssertEqual(RoomClipCache.videoVersion(recordedAt: nil, changeTag: "abc"), "tag:abc")
        XCTAssertNil(RoomClipCache.videoVersion(recordedAt: nil, changeTag: nil))
    }

    // MARK: - Disk

    func testManifestRoundTripsAndUnreadableManifestReadsEmpty() throws {
        XCTAssertEqual(RoomClipCache.loadManifest(in: dir), .init())
        let manifest = RoomClipCache.Manifest(versions: ["a": "v1", "b": "tag:x"])
        try RoomClipCache.saveManifest(manifest, in: dir)
        XCTAssertEqual(RoomClipCache.loadManifest(in: dir), manifest)

        try writeFile(RoomClipCache.manifestFileName, "{not json")
        XCTAssertEqual(RoomClipCache.loadManifest(in: dir), .init())
    }

    func testCachedNamesAreOnlyVideosAndRemovalLeavesTheRest() throws {
        try writeFile("ROOM_a_day1.mov", "a")
        try writeFile("ROOM_b_day1.mov", "b")
        try writeFile("ROOM_c_day1.mov.part", "partial")
        try RoomClipCache.saveManifest(.init(versions: ["ROOM_a_day1": "v1"]), in: dir)
        XCTAssertEqual(RoomClipCache.cachedRecordNames(in: dir), ["ROOM_a_day1", "ROOM_b_day1"])

        RoomClipCache.removeFiles(["ROOM_b_day1"], in: dir)
        XCTAssertEqual(RoomClipCache.cachedRecordNames(in: dir), ["ROOM_a_day1"])
        XCTAssertEqual(RoomClipCache.loadManifest(in: dir).versions, ["ROOM_a_day1": "v1"])
    }

    func testInstallReplacesTheTakeAndAFailedInstallKeepsTheOldOne() throws {
        let source = dir.appendingPathComponent("download.tmp")
        try Data("old".utf8).write(to: source)
        try RoomClipCache.install(source, recordName: "clip", in: dir)
        XCTAssertEqual(try contents(of: "clip"), "old")

        try Data("new".utf8).write(to: source, options: .atomic)
        try RoomClipCache.install(source, recordName: "clip", in: dir)
        XCTAssertEqual(try contents(of: "clip"), "new")

        let missing = dir.appendingPathComponent("never-downloaded.tmp")
        XCTAssertThrowsError(try RoomClipCache.install(missing, recordName: "clip", in: dir))
        XCTAssertEqual(try contents(of: "clip"), "new")
        XCTAssertEqual(RoomClipCache.cachedRecordNames(in: dir), ["clip"])
    }

    func testGenericMediaInstallKeepsItsNameAndCleansStagingFiles() throws {
        let source = dir.appendingPathComponent("download.tmp")
        let destination = dir.appendingPathComponent("avatar.png")
        try Data("old-avatar".utf8).write(to: destination)
        try Data("new-avatar".utf8).write(to: source)
        try RoomClipCache.install(source, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data("new-avatar".utf8))
        XCTAssertEqual(try Data(contentsOf: source), Data("new-avatar".utf8))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .contains { $0.hasSuffix(".part") })

        XCTAssertThrowsError(try RoomClipCache.install(
            dir.appendingPathComponent("missing"), to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), Data("new-avatar".utf8))

        try RoomClipCache.install(source, to: destination, consumingSource: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("new-avatar".utf8))
    }
}

/// How room syncs overlap: different rooms side by side up to a cap, the same
/// room never twice at once.
@MainActor
final class RoomSyncConcurrencyTests: XCTestCase {
    /// Counts how many fetches are running at once, per room and overall.
    private final class FetchMeter {
        var active = 0
        var peak = 0
        var activeByRoom: [String: Int] = [:]
        var peakForOneRoom = 0
        var fetched: [String] = []
    }

    private func transport(_ meter: FetchMeter) -> RoomSyncTransport {
        RoomSyncTransport(
            fetchClips: { code, _ in
                meter.active += 1
                meter.peak = max(meter.peak, meter.active)
                meter.activeByRoom[code, default: 0] += 1
                meter.peakForOneRoom = max(meter.peakForOneRoom, meter.activeByRoom[code]!)
                try await Task.sleep(nanoseconds: 40_000_000)
                meter.activeByRoom[code]! -= 1
                meter.active -= 1
                meter.fetched.append(code)
                return []
            },
            fetchInteractions: { _ in ([], []) },
            uploadClip: { _, _, _, _, _, _, _, _ in },
            updateClipCaption: { _, _, _, _, _ in },
            setReaction: { _, _, _, _, _, _, _ in },
            postComment: { _, _, _, _, _, _, _ in },
            deleteComment: { _ in })
    }

    private func room(_ code: String) -> Challenge {
        Challenge(
            id: UUID(), title: "Room \(code)",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            cards: [DayCard(day: 1, clipFileName: nil, recordedAt: nil)],
            mode: .oneDay, clipLength: .tiny, orientation: .portrait,
            momentTitles: ["Moment 1"],
            roomCode: code, ownerName: "Leo", ownerID: "owner-1")
    }

    func testSharedRoomsSyncSideBySideUpToTheCap() async throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        let meter = FetchMeter()
        let sync = RoomSyncService(fileStore: files, transport: transport(meter))
        let store = ChallengeStore(
            repository: files, fileStore: files,
            roomSync: sync, effects: .isolated)
        let codes = ["AAAAAA", "BBBBBB", "CCCCCC", "DDDDDD", "EEEEEE"]
        store.challenges = codes.map(room)

        await store.syncSharedRooms()

        XCTAssertEqual(Set(meter.fetched), Set(codes))
        XCTAssertEqual(meter.fetched.count, codes.count)
        XCTAssertEqual(meter.peak, ChallengeStore.sharedRoomSyncWidth)
        XCTAssertTrue(sync.syncing.isEmpty)
    }

    func testTheSameRoomIsNeverPulledTwiceAtOnce() async throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        let meter = FetchMeter()
        let sync = RoomSyncService(fileStore: files, transport: transport(meter))

        async let first = sync.syncClips(code: "ROOM")
        async let second = sync.syncClips(code: "ROOM")
        async let other = sync.syncClips(code: "OTHER")
        let results = await [first, second, other]

        XCTAssertEqual(results.map { $0?.count }, [0, 0, 0])
        XCTAssertEqual(meter.fetched.filter { $0 == "ROOM" }.count, 2,
                       "a waiting caller still gets a pull of its own, not the older result")
        XCTAssertEqual(meter.peakForOneRoom, 1)
        XCTAssertEqual(meter.peak, 2, "different rooms still overlap")
        XCTAssertTrue(sync.syncing.isEmpty)
    }
}
