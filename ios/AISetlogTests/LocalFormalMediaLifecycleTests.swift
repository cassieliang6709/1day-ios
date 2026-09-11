import AVFoundation
import XCTest
@testable import AISetlog

/// Exercises the same owner/media lease used by StoryTimelineView and FilmView.
/// Decoded file frames are not assertions about on-screen playback.
@MainActor
final class LocalFormalMediaLifecycleTests: XCTestCase {
    func testMemberSwitchRetiresOldRenderedCacheWithoutTouchingNewRoom() async throws {
        let epoch = AccountStore.identityRevision
        let owner = LocalRoomDemoOwner()
        defer { owner.close() }
        await owner.load(memberCount: 2, chinese: false)
        let first = try XCTUnwrap(owner.runtime)
        let oldScope = try XCTUnwrap(owner.media)
        let originals = first.store.recordedClips(for: first.challengeID)
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.showDayCaptions = false
        let output = try await VideoStitcher.stitch(clips: originals, options: options)
        XCTAssertTrue(oldScope.accept(output, key: "moment"))
        XCTAssertEqual(oldScope.cached("moment"), output)
        XCTAssertTrue(originals.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })

        await owner.load(memberCount: 3, chinese: true)
        let second = try XCTUnwrap(owner.runtime)
        let newScope = try XCTUnwrap(owner.media)
        XCTAssertTrue(first.isClosed)
        XCTAssertTrue(oldScope.isClosed)
        XCTAssertNil(oldScope.cached("moment"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.storage.root.path))
        XCTAssertNotEqual(first.challengeID, second.challengeID)
        let nextClips = second.store.recordedClips(for: second.challengeID)
        XCTAssertEqual(nextClips.count, 3)
        let nextOutput = try await VideoStitcher.stitch(clips: nextClips, options: options)
        XCTAssertTrue(newScope.accept(nextOutput, key: "moment"))
        oldScope.close()
        first.close()
        XCTAssertEqual(newScope.cached("moment"), nextOutput)
        let image = try await AVAssetImageGenerator(asset: AVURLAsset(url: nextOutput))
            .image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertTrue(nextClips.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
        owner.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: nextOutput.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.storage.root.path))
        XCTAssertEqual(AccountStore.identityRevision, epoch)
    }

    func testCompletedRealRenderDeliveredAfterDismissalIsDiscarded() async throws {
        let owner = LocalRoomDemoOwner()
        defer { owner.close() }
        await owner.load(memberCount: 2, chinese: false)
        let runtime = try XCTUnwrap(owner.runtime)
        let scope = try XCTUnwrap(owner.media)
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.showDayCaptions = false
        let output = try await VideoStitcher.stitch(
            clips: runtime.store.recordedClips(for: runtime.challengeID), options: options)
        // Deterministically model dismissal between export completion and its UI delivery.
        owner.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(scope.accept(output, key: "late"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertNil(scope.cached("late"))
        await owner.load(memberCount: 3, chinese: false)
        XCTAssertNil(owner.runtime)
        XCTAssertNil(owner.media)
        XCTAssertFalse(owner.failed)
    }
}
