import AVFoundation
import XCTest
@testable import AISetlog

final class VideoStitcherTests: XCTestCase {
    func testSequentialStitchExportsPlayableVideo() async throws {
        let clips = try sampleClips(count: 3)
        var options = VideoStitcher.Options()
        options.layout = .sequential
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

    func testGridStitchExportsConfiguredDuration() async throws {
        let clips = try sampleClips(count: 4)
        var options = VideoStitcher.Options()
        options.layout = .grid
        options.gridSeconds = 2.0
        options.showDayCaptions = false

        let output = try await VideoStitcher.stitch(clips: clips, options: options)
        defer { try? FileManager.default.removeItem(at: output) }

        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        XCTAssertEqual(duration, 2.0, accuracy: 0.1)
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

    private func sampleClips(count: Int) throws -> [DayClip] {
        try (1...count).map { day in
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: "day\(day)", withExtension: "mp4")
            )
            return DayClip(day: day, url: url, label: "Day \(day)")
        }
    }

    private func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return try XCTUnwrap(values.fileSize)
    }
}
