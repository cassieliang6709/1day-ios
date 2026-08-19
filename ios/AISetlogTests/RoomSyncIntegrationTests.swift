import AVFoundation
import CloudKit
import XCTest
@testable import AISetlog

/// The actual round trip, against the real CloudKit development database:
/// one person creates a room and uploads a clip, the other fetches the room by
/// code and gets that clip back with the right author on it.
///
/// This talks to the network and needs the device signed into iCloud, so it
/// skips itself rather than failing when it can't run — it isn't a test for an
/// unattended CI box. Everything it writes is cleaned up at the end.
final class RoomSyncIntegrationTests: XCTestCase {
    private let hostID = "test-host-\(UUID().uuidString)"
    private let guestID = "test-guest-\(UUID().uuidString)"
    private var createdCode: String?

    override func setUp() async throws {
        try await super.setUp()
        do {
            try await CloudKitService.ensureAccountAvailable()
        } catch {
            throw XCTSkip("Needs a simulator or device signed into iCloud: \(error)")
        }
    }

    override func tearDown() async throws {
        if let code = createdCode {
            for author in [hostID, guestID] {
                try? await CloudKitService.deleteMyRoomData(
                    authorID: author,
                    clips: (1...3).map { (code: code, day: $0) },
                    reactions: [],
                    commentIDs: [],
                    roomCodes: [code])
            }
        }
        try await super.tearDown()
    }

    func testAClipUploadedByOnePersonComesBackForTheOther() async throws {
        // Host creates the room.
        let room = try await CloudKitService.createRoom(
            title: "Sync test", ownerID: hostID, ownerName: "Test Host",
            momentTitles: ["Wake up", "Coffee", "Night"])
        createdCode = room.code
        XCTAssertEqual(room.code.count, 6)

        // Guest joins by code — a direct record fetch, no index needed.
        let joined = try await CloudKitService.fetchRoom(code: room.code)
        XCTAssertEqual(joined.title, "Sync test")
        XCTAssertEqual(joined.momentTitles, ["Wake up", "Coffee", "Night"])

        // Each of them films a different moment.
        let hostMade = await DemoClipFactory.makeClip(
            moment: 1, label: "Wake up", author: "Test Host",
            seconds: 2, orientation: .portrait)
        let guestMade = await DemoClipFactory.makeClip(
            moment: 2, label: "Coffee", author: "Test Guest",
            seconds: 2, orientation: .portrait)
        let hostClip = try XCTUnwrap(hostMade)
        let guestClip = try XCTUnwrap(guestMade)

        try await CloudKitService.uploadClip(
            code: room.code, day: 1, authorID: hostID, authorName: "Test Host",
            fileURL: hostClip, overlayText: "from the host")
        try await CloudKitService.uploadClip(
            code: room.code, day: 2, authorID: guestID, authorName: "Test Guest",
            fileURL: guestClip)

        // Either side pulling the room sees both, ordered by moment. `fetchClips`
        // runs a CKQuery, and CloudKit's query index is eventually consistent —
        // a clip that just uploaded can be missing from the next query for a
        // while, so poll instead of asserting on one shot.
        let pulled = try await waitForClips(in: room.code, count: 2)

        XCTAssertEqual(pulled.map(\.day), [1, 2])
        XCTAssertEqual(pulled.map(\.authorID), [hostID, guestID])
        XCTAssertEqual(pulled.first?.overlayText, "from the host")
        for clip in pulled {
            let duration = try await AVURLAsset(url: clip.localURL).load(.duration).seconds
            XCTAssertEqual(duration, 2, accuracy: 0.2, "downloaded asset should be playable")
        }
    }

    /// Polls until the room reports at least `count` clips, or gives up and
    /// returns whatever it last saw so the assertion can show the shortfall.
    private func waitForClips(
        in code: String,
        count: Int,
        timeout: TimeInterval = 120
    ) async throws -> [CloudKitService.RemoteClip] {
        let deadline = Date().addingTimeInterval(timeout)
        var latest: [CloudKitService.RemoteClip] = []
        while Date() < deadline {
            let cache = FileManager.default.temporaryDirectory
                .appendingPathComponent("sync-poll-\(UUID().uuidString)")
            latest = (try? await CloudKitService.fetchClips(code: code, into: cache)) ?? []
            if latest.count >= count { return latest }
            try? await Task.sleep(for: .seconds(5))
        }
        return latest
    }

    /// Clip record names are `code_author_dayN`, so re-recording a moment has
    /// to replace the clip rather than add a second one.
    func testReRecordingAMomentReplacesTheClip() async throws {
        let room = try await CloudKitService.createRoom(
            title: "Re-record test", ownerID: hostID, ownerName: "Test Host")
        createdCode = room.code

        for take in 1...2 {
            let made = await DemoClipFactory.makeClip(
                moment: 1, label: "Take \(take)", author: "Test Host",
                seconds: 2, orientation: .portrait)
            let clip = try XCTUnwrap(made)
            try await CloudKitService.uploadClip(
                code: room.code, day: 1, authorID: hostID, authorName: "Test Host",
                fileURL: clip, overlayText: "take \(take)")
        }

        let pulled = try await waitForClips(in: room.code, count: 1)

        XCTAssertEqual(pulled.count, 1, "a re-record should overwrite, not append")
        XCTAssertEqual(pulled.first?.overlayText, "take 2")
    }
}
