import AVFoundation
import XCTest
@testable import AISetlog

@MainActor
final class LocalRoomImportTests: XCTestCase {
    func testReplaceEachMemberPreservesOthersIdentitySourceAndDefaultAspect() async throws {
        let runtime = try await LocalRoomRuntime.make(memberCount: 3, chinese: true)
        defer { runtime.close() }
        let generated = await DemoClipFactory.makeClip(moment: 1, label: "Landscape", author: "Fixture",
            seconds: 4, orientation: .landscape)
        let input = try XCTUnwrap(generated)
        defer { try? FileManager.default.removeItem(at: input) }
        let bytes = try Data(contentsOf: input)
        let initial = runtime.store.recordedClips(for: runtime.challengeID)
        for target in initial {
            let before = runtime.store.recordedClips(for: runtime.challengeID)
            try await runtime.replaceClip(authorID: try XCTUnwrap(target.authorID), from: input)
            let after = runtime.store.recordedClips(for: runtime.challengeID)
            XCTAssertEqual(after.map(\.id), before.map(\.id))
            for old in before {
                let new = try XCTUnwrap(after.first { $0.id == old.id })
                XCTAssertEqual(new.authorID, old.authorID)
                XCTAssertEqual(new.authorName, old.authorName)
                if old.id == target.id {
                    XCTAssertNotEqual(new.url, old.url)
                    let duration = try await AVURLAsset(url: new.url).load(.duration).seconds
                    XCTAssertEqual(duration, 3, accuracy: 0.1)
                } else { XCTAssertEqual(new.url, old.url) }
                XCTAssertTrue(FileManager.default.fileExists(atPath: old.url.path), "old player lease survives")
            }
            XCTAssertEqual(try Data(contentsOf: input), bytes)
            await runtime.store.syncRoom(runtime.challengeID)
            XCTAssertEqual(runtime.store.recordedClips(for: runtime.challengeID).map(\.url), after.map(\.url))
        }
        let own = try XCTUnwrap(runtime.store.recordedClips(for: runtime.challengeID).first { $0.authorID == runtime.account.account?.id })
        let card = try XCTUnwrap(runtime.store.challenge(runtime.challengeID)?.cards.first)
        XCTAssertEqual(runtime.storage.clipURL(fileName: try XCTUnwrap(card.clipFileName), challengeID: runtime.challengeID), own.url)
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.showDayCaptions = false
        let output = try await VideoStitcher.stitch(clips: runtime.store.recordedClips(for: runtime.challengeID), options: options)
        runtime.ownDerivedMedia(output)
        let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
        let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
        XCTAssertGreaterThan(size.height, size.width, "landscape input keeps approved opposite default")
    }

    func testInvalidAndCancelledImportsLeaveAllClipsAndSourceUntouched() async throws {
        let runtime = try await LocalRoomRuntime.make(memberCount: 2, chinese: false)
        defer { runtime.close() }
        let before = runtime.store.recordedClips(for: runtime.challengeID)
        let input = runtime.storage.root.appendingPathComponent("invalid.mov")
        let bytes = Data("not a movie".utf8)
        try bytes.write(to: input)
        do {
            try await runtime.replaceClip(authorID: try XCTUnwrap(before.first?.authorID), from: input)
            XCTFail("invalid media accepted")
        } catch {}
        let task = Task { @MainActor in
            try await runtime.replaceClip(authorID: try XCTUnwrap(before.first?.authorID), from: input,
                prepare: { _ in throw CancellationError() })
        }
        do { try await task.value; XCTFail("cancel accepted") } catch {}
        XCTAssertEqual(runtime.store.recordedClips(for: runtime.challengeID).map(\.url), before.map(\.url))
        XCTAssertEqual(try Data(contentsOf: input), bytes)
    }

    func testDismissWhilePreparingDiscardsLateOutputWithoutResurrectingRuntime() async throws {
        let runtime = try await LocalRoomRuntime.make(memberCount: 2, chinese: false)
        let clip = try XCTUnwrap(runtime.store.recordedClips(for: runtime.challengeID).first)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("local-import-test-\(UUID()).mov")
        try Data("prepared".utf8).write(to: output)
        defer { try? FileManager.default.removeItem(at: output) }
        do {
            try await runtime.replaceClip(authorID: try XCTUnwrap(clip.authorID), from: clip.url, prepare: { _ in
                runtime.close()
                return output
            })
            XCTFail("closed runtime accepted output")
        } catch {}
        XCTAssertTrue(runtime.store.challenges.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.storage.root.path))
    }
}
