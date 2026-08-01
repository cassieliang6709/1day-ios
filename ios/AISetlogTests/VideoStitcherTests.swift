import AVFoundation
import XCTest
@testable import AISetlog

final class VideoStitcherTests: XCTestCase {
    func testSequentialStitchExportsPlayableVideo() async throws {
        let clips = try await sampleClips(count: 3)
        var options = VideoStitcher.Options()
        options.crossfadeSeconds = 0.3
        options.showDayCaptions = false

        let output = try await VideoStitcher.stitch(clips: clips, options: options)
        defer { try? FileManager.default.removeItem(at: output) }

        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        XCTAssertFalse(videoTracks.isEmpty)
        XCTAssertGreaterThan(duration, 4.0)
        XCTAssertLessThan(duration, 6.1)
        XCTAssertGreaterThan(try fileSize(output), 0)
    }

    func testFriendsTogetherPlaysSameDayClipsSimultaneously() async throws {
        let made = await DemoClipFactory.makeClip(index: 0)
        let source = try XCTUnwrap(made)
        defer { try? FileManager.default.removeItem(at: source) }
        let clips = [
            DayClip(day: 1, url: source, authorName: "A"),
            DayClip(day: 1, url: source, authorName: "B"),
        ]
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.showDayCaptions = false

        let output = try await VideoStitcher.stitch(clips: clips, options: options)
        defer { try? FileManager.default.removeItem(at: output) }

        let sourceDuration = try await AVURLAsset(url: source).load(.duration).seconds
        let outputDuration = try await AVURLAsset(url: output).load(.duration).seconds
        XCTAssertEqual(outputDuration, sourceDuration, accuracy: 0.15)
        XCTAssertGreaterThan(try fileSize(output), 0)
    }

    func testStitchRejectsEmptyInput() async {
        do {
            _ = try await VideoStitcher.stitch(clips: [])
            XCTFail("Expected an empty-input error")
        } catch VideoStitcher.StitchError.noClips {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Fixtures are generated rather than bundled: the seven `day*.mp4` files
    /// these used to load existed only for development, and shipped inside
    /// every release build to serve these tests and a debug menu item.
    private func sampleClips(count: Int) async throws -> [DayClip] {
        var clips: [DayClip] = []
        for day in 1...count {
            let made = await DemoClipFactory.makeClip(index: day - 1)
            let url = try XCTUnwrap(made)
            clips.append(DayClip(day: day, url: url, label: "Day \(day)"))
        }
        return clips
    }

    private func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return try XCTUnwrap(values.fileSize)
    }
}
