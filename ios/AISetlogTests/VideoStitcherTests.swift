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
        let made = await ClipFixtureFactory.makeClip(index: 0)
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

    // MARK: - Sequential framing

    private let portraitCanvas = CGSize(width: 1080, height: 1920)

    func testLandscapeTakeInAPortraitFilmIsShownWholeAndCentred() throws {
        let framing = VideoStitcher.sequentialFraming(
            orientedSize: CGSize(width: 1920, height: 1080), canvas: portraitCanvas)
        guard case .fitOnBed(let subject) = framing else {
            return XCTFail("a 16:9 take was cropped to fill a 9:16 film: \(framing)")
        }
        let canvas = CGRect(origin: .zero, size: portraitCanvas)
        XCTAssertTrue(canvas.insetBy(dx: -0.5, dy: -0.5).contains(subject), "\(subject)")
        XCTAssertEqual(subject.width, 1080, accuracy: 0.5)
        XCTAssertEqual(subject.height, 607.5, accuracy: 0.5)
        XCTAssertEqual(subject.width / subject.height, 16.0 / 9, accuracy: 0.001)
        XCTAssertEqual(subject.midX, canvas.midX, accuracy: 0.5)
        XCTAssertEqual(subject.midY, canvas.midY, accuracy: 0.5)
    }

    func testTakeOfTheCanvasShapeStillFills() {
        XCTAssertEqual(
            VideoStitcher.sequentialFraming(orientedSize: portraitCanvas, canvas: portraitCanvas),
            .fill)
        // A few pixels off the canvas's shape is inside the tolerance.
        XCTAssertEqual(
            VideoStitcher.sequentialFraming(
                orientedSize: CGSize(width: 1072, height: 1920), canvas: portraitCanvas),
            .fill)
    }

    func testCameraStyleTakesInANineBySixteenFilmAreShownWhole() {
        for take in [CGSize(width: 1080, height: 1440), CGSize(width: 1080, height: 1620)] {
            guard case .fitOnBed(let subject) = VideoStitcher.sequentialFraming(
                orientedSize: take, canvas: portraitCanvas)
            else { return XCTFail("\(take) was cropped to fill a 9:16 film") }
            // Taller than wide but wider than the canvas: fitted to the width.
            XCTAssertEqual(subject.width, 1080, accuracy: 0.5)
            XCTAssertEqual(subject.midY, 960, accuracy: 0.5)
        }
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
    /// these used to load shipped inside every release build.
    private func sampleClips(count: Int) async throws -> [DayClip] {
        var clips: [DayClip] = []
        for day in 1...count {
            let made = await ClipFixtureFactory.makeClip(index: day - 1)
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
