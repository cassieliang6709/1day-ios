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

    func testOneUpKeepsTheShapeItWasFilmedIn() async throws {
        let portrait = try await fixture(.portrait)
        let portraitFilm = try await render([portrait, portrait], layout: .sequential)
        XCTAssertEqual(portraitFilm.width / portraitFilm.height, 9.0 / 16, accuracy: 0.01)

        let landscape = try await fixture(.landscape)
        let landscapeFilm = try await render([landscape, landscape], layout: .sequential)
        XCTAssertEqual(landscapeFilm.width / landscapeFilm.height, 16.0 / 9, accuracy: 0.01)
    }

    func testTwoUpCanvasFollowsTheSplitItNeeds() async throws {
        let portrait = try await fixture(.portrait)
        let sideBySide = try await render([portrait, portrait], layout: .friendsTogether)
        XCTAssertEqual(sideBySide.width / sideBySide.height, 9.0 / 8, accuracy: 0.02)

        let landscape = try await fixture(.landscape)
        let stacked = try await render([landscape, landscape], layout: .friendsTogether)
        XCTAssertEqual(stacked.width / stacked.height, 8.0 / 9, accuracy: 0.02)
    }

    func testCanvasIsSetByTheBusiestMomentNotTheClipCount() async throws {
        let portrait = try await fixture(.portrait)
        let clips = [
            DayClip(day: 1, url: portrait, authorName: "A", authorID: "a", key: "a"),
            DayClip(day: 2, url: portrait, authorName: "B", authorID: "b", key: "b"),
        ]
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.showDayCaptions = false
        options.crossfadeSeconds = 0
        let film = try await VideoStitcher.stitch(clips: clips, options: options)
        owned.append(film)
        let tracks = try await AVURLAsset(url: film).loadTracks(withMediaType: .video)
        let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
        XCTAssertEqual(size.width / size.height, 9.0 / 16, accuracy: 0.01)
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
        XCTAssertLessThan(
            film.width, film.height,
            "A single visible-portrait take must come out portrait, whatever the file encodes")
    }

    @MainActor
    func testDemoAutoUpdatesAfterFirstMemberReplacementAndAllowsOverride() async throws {
        let model = RoomVideoDemoModel()
        defer { model.close() }
        await model.prepare(count: 2, chinese: true, clipSeconds: DemoHarness.clipSeconds)
        XCTAssertFalse(model.failed)
        XCTAssertGreaterThan(model.filmRatio, 1)
        let replacement = try await fixture(.landscape)
        await model.replace(index: 0, source: replacement, count: 2, chinese: true)
        XCTAssertFalse(model.failed)
        XCTAssertLessThan(model.filmRatio, 1)
        await model.prepare(count: 2, landscape: true, chinese: true, clipSeconds: DemoHarness.clipSeconds)
        XCTAssertFalse(model.failed)
        XCTAssertGreaterThan(model.filmRatio, 1)
    }


    func testSquareTakesKeepASquareCanvasWhereTheGridAllowsIt() throws {
        for count in [1, 4] {
            let size = VideoStitcher.mosaicRenderSize(
                count: count, sourceAspect: 1, longEdge: 960)
            XCTAssertEqual(
                size.width / size.height, 1, accuracy: 0.01,
                "\(count)-up square should stay square")
        }
    }

    func testTwoSquareTakesStackWithoutCropping() throws {
        let size = VideoStitcher.mosaicRenderSize(count: 2, sourceAspect: 1, longEdge: 960)
        XCTAssertEqual(size.width / size.height, 0.5, accuracy: 0.01)
    }

    func testThreeSquareTakesFallBackToTheTakesOwnShape() throws {
        let square = VideoStitcher.mosaicRenderSize(count: 3, sourceAspect: 1, longEdge: 960)
        XCTAssertEqual(square.width / square.height, 1, accuracy: 0.01)

        let portrait = VideoStitcher.mosaicRenderSize(
            count: 3, sourceAspect: 9.0 / 16, longEdge: 960)
        XCTAssertEqual(portrait.width / portrait.height, 27.0 / 16, accuracy: 0.02)

        let landscape = VideoStitcher.mosaicRenderSize(
            count: 3, sourceAspect: 16.0 / 9, longEdge: 960)
        XCTAssertEqual(landscape.width / landscape.height, 16.0 / 27, accuracy: 0.02)
    }

    func testSquareCropTurnsAPortraitTakeSquareAndKeepsItsLength() async throws {
        let portrait = try await fixture(.portrait)
        let before = try await AVURLAsset(url: portrait).load(.duration).seconds

        let cropped = await SquareCrop.copy(of: portrait)
        owned.append(cropped)
        XCTAssertNotEqual(cropped, portrait, "a portrait take must not come back unchanged")

        let tracks = try await AVURLAsset(url: cropped).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let visible = CGRect(origin: .zero, size: natural).applying(transform)
        XCTAssertEqual(abs(visible.width) / abs(visible.height), 1, accuracy: 0.01)

        let after = try await AVURLAsset(url: cropped).load(.duration).seconds
        XCTAssertEqual(after, before, accuracy: 0.1, "the crop must not trim the take")
    }

    func testSquareCropReturnsTheOriginalWhenItCannotWork() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-clip-\(UUID().uuidString).mov")
        let result = await SquareCrop.copy(of: missing)
        XCTAssertEqual(result, missing)
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
