import AVFoundation
import XCTest
@testable import AISetlog

@MainActor
final class BackgroundFilmExportTests: XCTestCase {
    func testCancelledPageStillFinishesAPlayableFilmAndReusesIt() async throws {
        let generated = await ClipFixtureFactory.makeClip(index: 1)
        let source = try XCTUnwrap(generated)
        defer { try? FileManager.default.removeItem(at: source) }
        let clips = [DayClip(day: 1, url: source)]
        var options = VideoStitcher.Options()
        options.showDayCaptions = false
        let renderer = BackgroundFilmExport()
        let page = Task { try await renderer.render(clips: clips, options: options) }
        page.cancel()
        let film = try await page.value
        defer { try? FileManager.default.removeItem(at: film.deletingLastPathComponent()) }
        let tracks = try await AVURLAsset(url: film).loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            film.deletingLastPathComponent().appendingPathComponent("inputs").path))
        let afterRelaunch = BackgroundFilmExport()
        let recovered = try await afterRelaunch.render(clips: clips, options: options)
        XCTAssertEqual(recovered, film)
    }

    func testCancelledExportDoesNotStartWritingAnOutput() async throws {
        let generated = await ClipFixtureFactory.makeClip(index: 2)
        let source = try XCTUnwrap(generated)
        defer { try? FileManager.default.removeItem(at: source) }
        let session = try XCTUnwrap(AVAssetExportSession(
            asset: AVURLAsset(url: source), presetName: AVAssetExportPresetHighestQuality))
        let output = source.deletingLastPathComponent().appendingPathComponent("cancelled-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: output) }
        session.outputURL = output
        session.outputFileType = .mov
        let operation = Task { try await VideoExportOperation.run(session) }
        operation.cancel()
        do {
            try await operation.value
            XCTFail("Cancelled export completed")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testAccountChangeClearsThePreviousExportBeforeRenderingAgain() async throws {
        let generated = await ClipFixtureFactory.makeClip(index: 4)
        let source = try XCTUnwrap(generated)
        defer { try? FileManager.default.removeItem(at: source) }
        let clips = [DayClip(day: 1, url: source)]
        var options = VideoStitcher.Options()
        options.showDayCaptions = false
        let renderer = BackgroundFilmExport()
        let original = try await renderer.render(clips: clips, options: options)
        defer { try? FileManager.default.removeItem(at: original.deletingLastPathComponent()) }
        renderer.resetForAccountChange()
        var renderedAgain = false
        let fresh = try await renderer.render(clips: clips, options: options) { _, _ in
            renderedAgain = true
        }
        XCTAssertEqual(fresh, original)
        XCTAssertTrue(renderedAgain)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }
}
