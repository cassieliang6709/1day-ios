import AVFoundation
import XCTest
@testable import AISetlog

final class DefaultFilmAspectTests: XCTestCase {
    private var owned: [URL] = []

    override func tearDown() {
        owned.forEach { try? FileManager.default.removeItem(at: $0) }
        owned = []
        super.tearDown()
    }

    func testAutomaticPolicyAndSquareFallback() {
        XCTAssertEqual(VideoStitcher.Aspect.defaultForSource(CGSize(width: 540, height: 960)), .landscape)
        XCTAssertEqual(VideoStitcher.Aspect.defaultForSource(CGSize(width: 960, height: 540)), .portrait)
        XCTAssertNil(VideoStitcher.Aspect.defaultForSource(CGSize(width: 640, height: 640)))
    }

    func testPortraitSourcesDefaultToLandscapeForBothLayouts() async throws {
        let source = try await fixture(.portrait)
        for layout in [VideoStitcher.Layout.sequential, .friendsTogether] {
            let size = try await render([source, source], layout: layout)
            XCTAssertEqual(size.width / size.height, 16.0 / 9, accuracy: 0.01)
        }
    }

    func testLandscapeSourcesDefaultToPortraitForBothLayouts() async throws {
        let source = try await fixture(.landscape)
        for layout in [VideoStitcher.Layout.sequential, .friendsTogether] {
            let size = try await render([source, source], layout: layout)
            XCTAssertEqual(size.width / size.height, 9.0 / 16, accuracy: 0.01)
        }
    }

    func testExplicitPortraitAndSquareOverrideAutomaticChoice() async throws {
        let source = try await fixture(.portrait)
        let portrait = try await render([source], aspect: .portrait)
        XCTAssertLessThan(portrait.width, portrait.height)
        let square = try await render([source], aspect: .square)
        XCTAssertEqual(square.width, square.height)
    }

    func testMixedSourcesUseFirstSourceDirectionDeterministically() async throws {
        let portrait = try await fixture(.portrait)
        let landscape = try await fixture(.landscape)
        let a = try await render([portrait, landscape])
        let b = try await render([landscape, portrait])
        XCTAssertGreaterThan(a.width, a.height)
        XCTAssertLessThan(b.width, b.height)
    }

    func testPreferredTransformDeterminesDirectionNotEncodedDimensions() async throws {
        let original = try await fixture(.landscape)
        let asset = AVURLAsset(url: original)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let source = try XCTUnwrap(tracks.first)
        let range = try await source.load(.timeRange)
        let composition = AVMutableComposition()
        let track = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try track.insertTimeRange(range, of: source, at: .zero)
        track.preferredTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 540, ty: 0)
        let rotated = FileManager.default.temporaryDirectory.appendingPathComponent("aspect-rotated-\(UUID()).mov")
        owned.append(rotated)
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        exporter.outputURL = rotated
        exporter.outputFileType = .mov
        await exporter.export()
        XCTAssertEqual(exporter.status, .completed)
        let rotatedTracks = try await AVURLAsset(url: rotated).loadTracks(withMediaType: .video)
        let rotatedTrack = try XCTUnwrap(rotatedTracks.first)
        let encoded = try await rotatedTrack.load(.naturalSize)
        let transform = try await rotatedTrack.load(.preferredTransform)
        let visible = CGRect(origin: .zero, size: encoded).applying(transform)
        XCTAssertGreaterThan(encoded.width, encoded.height)
        XCTAssertGreaterThan(abs(visible.height), abs(visible.width))
        let film = try await render([rotated])
        XCTAssertGreaterThan(film.width, film.height, "Visible portrait input must default to landscape output")
    }

    @MainActor
    func testDemoAutoUpdatesAfterFirstMemberReplacementAndAllowsOverride() async throws {
        let model = RoomVideoDemoModel()
        defer { model.close() }
        await model.prepare(count: 2, chinese: true)
        XCTAssertFalse(model.failed)
        XCTAssertGreaterThan(model.filmRatio, 1)
        let replacement = try await fixture(.landscape)
        await model.replace(index: 0, source: replacement, count: 2, chinese: true)
        XCTAssertFalse(model.failed)
        XCTAssertLessThan(model.filmRatio, 1)
        await model.prepare(count: 2, landscape: true, chinese: true)
        XCTAssertFalse(model.failed)
        XCTAssertGreaterThan(model.filmRatio, 1)
    }

    private func fixture(_ orientation: Challenge.Orientation) async throws -> URL {
        let made = await DemoClipFactory.makeClip(moment: 1, label: "Aspect fixture", author: "Sample", seconds: 0.5, orientation: orientation)
        let url = try XCTUnwrap(made)
        owned.append(url)
        return url
    }

    private func render(_ urls: [URL], layout: VideoStitcher.Layout = .friendsTogether,
                        aspect: VideoStitcher.Aspect? = nil) async throws -> CGSize {
        var options = VideoStitcher.Options()
        options.layout = layout
        options.aspect = aspect
        options.showDayCaptions = false
        options.crossfadeSeconds = 0
        let clips = urls.enumerated().map { index, url in
            DayClip(day: 1, url: url, authorName: "Sample \(index)", authorID: "sample-\(index)", key: "sample-\(index)")
        }
        let film = try await VideoStitcher.stitch(clips: clips, options: options)
        owned.append(film)
        let tracks = try await AVURLAsset(url: film).loadTracks(withMediaType: .video)
        return try await XCTUnwrap(tracks.first).load(.naturalSize)
    }
}
