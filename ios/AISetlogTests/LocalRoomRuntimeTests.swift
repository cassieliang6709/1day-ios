import AVFoundation
import XCTest
@testable import AISetlog

@MainActor
final class LocalRoomRuntimeTests: XCTestCase {
    func testTwoAndThreeMembersUseRealStoreAndCompositorThenCleanUp() async throws {
        let epoch = AccountStore.identityRevision
        for count in [2, 3] {
            let runtime = try await LocalRoomRuntime.make(memberCount: count, chinese: true)
            defer { runtime.close() }
            let clips = runtime.store.recordedClips(for: runtime.challengeID)
            XCTAssertEqual(clips.count, count)
            XCTAssertEqual(Set(clips.map(\.id)).count, count)
            XCTAssertEqual(runtime.store.members(for: runtime.challengeID).count, count)
            XCTAssertTrue(clips.allSatisfy { $0.url.path.hasPrefix(runtime.storage.root.path + "/") })
            var options = VideoStitcher.Options()
            options.layout = .friendsTogether
            options.showDayCaptions = false
            let output = try await VideoStitcher.stitch(clips: clips, options: options)
            runtime.ownDerivedMedia(output)
            let asset = AVURLAsset(url: output)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let size = try await track.load(.naturalSize)
            XCTAssertGreaterThan(size.width, size.height, "approved portrait-source → landscape default")
            let image = try await AVAssetImageGenerator(asset: asset).image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            XCTAssertGreaterThan(image.width, 0, "real compositor output decodes; not UI pixel evidence")
            let messages = try await runtime.chat.fetch(roomCode: runtime.chat.scope.roomCode)
            XCTAssertFalse(messages.isEmpty)
            XCTAssertEqual(runtime.account.account?.id, runtime.chat.scope.accountID)
            runtime.preferences.set("local", forKey: "test.preference")
            let root = runtime.storage.root
            runtime.close()
            runtime.close()
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertTrue(runtime.store.challenges.isEmpty)
            XCTAssertNil(runtime.preferences.string(forKey: "test.preference"))
            XCTAssertEqual(AccountStore.identityRevision, epoch)
        }
    }

    func testConcurrentRuntimesAndDraftsRemainIndependent() async throws {
        let first = try await LocalRoomRuntime.make(memberCount: 2, chinese: false)
        let second = try await LocalRoomRuntime.make(memberCount: 2, chinese: false)
        defer { first.close(); second.close() }
        let clip = try XCTUnwrap(first.store.recordedClips(for: first.challengeID).first)
        let draft = try first.drafts.keep(tempURL: clip.url, orientation: .portrait, overlayText: "Only mine")
        XCTAssertEqual(first.drafts.count, 1)
        XCTAssertEqual(second.drafts.count, 0)
        XCTAssertNotEqual(first.storage.root, second.storage.root)
        XCTAssertTrue(first.drafts.url(for: draft).path.hasPrefix(first.storage.root.path + "/"))
        let secondClip = try XCTUnwrap(second.store.recordedClips(for: second.challengeID).first)
        first.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondClip.url.path))
        XCTAssertEqual(second.store.recordedClips(for: second.challengeID).count, 2)
        XCTAssertThrowsError(try first.drafts.keep(tempURL: secondClip.url, orientation: .portrait))
        let lateOutput = second.storage.root.appendingPathComponent("late-output.mov")
        try Data("test render".utf8).write(to: lateOutput)
        first.ownDerivedMedia(lateOutput)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lateOutput.path))
        let session = RoomChatSession(scope: second.chat.scope, directory: second.chat.directory,
                                      transport: second.chat, identityIsCurrent: { !second.isClosed })
        await session.refresh()
        session.setDraft("Local message")
        await session.send(authorName: "Sample", moment: nil)
        XCTAssertTrue(session.state?.orderedEntries.contains { $0.message.text == "Local message" } == true)
    }
}
