import AVFoundation
import XCTest
@testable import AISetlog

/// End-to-end for the thing a shared room exists to produce: two people fill
/// alternating moments, and the stitcher folds both sets into one film in the
/// right order.
///
/// Frames from the finished film are written into the app's Caches directory so
/// a failure can be looked at rather than guessed at.
final class SharedRoomFilmTests: XCTestCase {
    private let mine = "iPhone 17 Pro Max"
    private let theirs = "1DAY-B"

    private func room(moments: Int) async throws -> [DayClip] {
        var clips: [DayClip] = []
        for moment in 1...moments {
            // Alternating, the way two people actually split a day.
            let author = moment.isMultiple(of: 2) ? theirs : mine
            let made = await DemoClipFactory.makeClip(
                moment: moment, label: "Moment \(moment)", author: author,
                seconds: 2, orientation: .portrait)
            clips.append(DayClip(
                day: moment, url: try XCTUnwrap(made),
                authorName: author, authorID: author))
        }
        return clips
    }

    func testBothAuthorsClipsLandInOneFilmInOrder() async throws {
        let clips = try await room(moments: 6)
        var options = VideoStitcher.Options()
        options.crossfadeSeconds = 0.3
        options.showDayCaptions = false

        let film = try await VideoStitcher.stitch(clips: clips, options: options)
        let asset = AVURLAsset(url: film)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)

        XCTAssertFalse(tracks.isEmpty)
        // Six 2s clips minus five 0.3s crossfades.
        XCTAssertEqual(duration, 12 - 5 * 0.3, accuracy: 0.35)

        // Sample the middle of each 1.7s slot: every clip must have made it in,
        // and consecutive slots must differ (authors alternate, colours differ).
        var samples: [Data] = []
        for slot in 0..<6 {
            let seconds = Double(slot) * 1.7 + 0.85
            samples.append(try await frame(of: film, at: seconds, saveAs: "film-slot-\(slot + 1)"))
        }
        for (index, pair) in zip(samples, samples.dropFirst()).enumerated() {
            XCTAssertNotEqual(pair.0, pair.1, "slots \(index + 1) and \(index + 2) look identical")
        }
    }

    func testFriendsTogetherPutsBothAuthorsOnScreenAtOnce() async throws {
        let mineClip = await DemoClipFactory.makeClip(
            moment: 1, label: "Wake up", author: mine, seconds: 2, orientation: .portrait)
        let theirsClip = await DemoClipFactory.makeClip(
            moment: 1, label: "Wake up", author: theirs, seconds: 2, orientation: .portrait)
        let clips = [
            DayClip(day: 1, url: try XCTUnwrap(mineClip), authorName: mine, authorID: mine),
            DayClip(day: 1, url: try XCTUnwrap(theirsClip), authorName: theirs, authorID: theirs),
        ]
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        // No aspect named: the canvas comes from the takes, which for two
        // portrait takes means 9:8 with a 9:16 cell each.
        options.showDayCaptions = false

        let film = try await VideoStitcher.stitch(clips: clips, options: options)
        let duration = try await AVURLAsset(url: film).load(.duration).seconds

        // Same moment from two people plays once, together — not back to back.
        XCTAssertEqual(duration, 2, accuracy: 0.2)

        // And side by side, each in a cell its own shape.
        let image = try await frameImage(of: film, at: 1, saveAs: "friends-together")
        // Below the stamped name and moment, above the sweeping progress bar:
        // flat tint, which is what tells the two authors apart.
        let left = pixel(image, atX: 0.25, y: 0.68)
        let right = pixel(image, atX: 0.75, y: 0.68)
        XCTAssertNotEqual(left, right, "the two authors should stand side by side")

        // The take fills its cell, so the outer edge of a cell is that person's
        // own footage rather than a bed or a bar — no crop, no padding.
        let outerEdge = pixel(image, atX: 0.02, y: 0.68)
        XCTAssertLessThan(
            distance(outerEdge, left), distance(outerEdge, right),
            "the edge of a cell should be that cell's own take")
    }

    /// How far apart two sampled pixels are, summed over the channels.
    private func distance(_ a: [UInt8], _ b: [UInt8]) -> Int {
        zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
    }

    func testGridSplitsAcrossTheTakesShortEdgeThenSquaresOff() {
        let portrait = 9.0 / 16
        let landscape = 16.0 / 9
        func assertGrid(
            _ count: Int, source: CGFloat, rows: Int, columns: Int,
            line: UInt = #line
        ) {
            let actual = VideoStitcher.grid(for: count, sourceAspect: source)
            XCTAssertEqual(actual.rows, rows, "rows for \(count)", line: line)
            XCTAssertEqual(actual.columns, columns, "columns for \(count)", line: line)
        }

        // Portrait takes stand side by side, landscape takes stack: either way
        // the cell keeps the take's own shape, which is what lets the mosaic
        // crop nobody.
        assertGrid(1, source: portrait, rows: 1, columns: 1)
        assertGrid(2, source: portrait, rows: 1, columns: 2)
        assertGrid(3, source: portrait, rows: 1, columns: 3)
        assertGrid(2, source: landscape, rows: 2, columns: 1)
        assertGrid(3, source: landscape, rows: 3, columns: 1)

        // Past three a strip is too narrow to see a person in.
        assertGrid(4, source: portrait, rows: 2, columns: 2)
        assertGrid(4, source: landscape, rows: 2, columns: 2)
    }

    /// The canvas exists to make the cells match the takes. Two portrait takes
    /// side by side is 9:8, four is 9:16 again — and in both the cell comes
    /// back out at 9:16, which is the whole point.
    func testMosaicCanvasGivesEveryCellTheShapeOfTheTakes() {
        func assertCells(
            _ count: Int, source: CGFloat, canvas: CGFloat, line: UInt = #line
        ) {
            let size = VideoStitcher.mosaicRenderSize(
                count: count, sourceAspect: source, longEdge: 1920)
            let split = VideoStitcher.grid(for: count, sourceAspect: source)
            XCTAssertEqual(size.width / size.height, canvas, accuracy: 0.01,
                           "canvas for \(count)", line: line)
            let cell = (size.width / CGFloat(split.columns))
                / (size.height / CGFloat(split.rows))
            XCTAssertEqual(cell, source, accuracy: 0.01, "cell for \(count)", line: line)
            XCTAssertEqual(max(size.width, size.height), 1920, accuracy: 2,
                           "long edge for \(count)", line: line)
        }

        let portrait = 9.0 / 16
        assertCells(1, source: portrait, canvas: 9.0 / 16)
        assertCells(2, source: portrait, canvas: 9.0 / 8)
        assertCells(3, source: portrait, canvas: 27.0 / 16)
        assertCells(4, source: portrait, canvas: 9.0 / 16)

        let landscape = 16.0 / 9
        assertCells(2, source: landscape, canvas: 8.0 / 9)
        assertCells(4, source: landscape, canvas: 16.0 / 9)
    }

    /// Grabs a frame, saves a PNG into Caches for inspection (Documents is the
    /// app's own storage — test output doesn't belong there), and returns its
    /// pixels for comparison.
    /// Colour at a proportional point in the frame, for asking "who is where".
    private func pixel(_ image: CGImage, atX x: Double, y: Double) -> [UInt8] {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return [] }
        let px = Int(Double(image.width) * x)
        let py = Int(Double(image.height) * y)
        let offset = py * image.bytesPerRow + px * (image.bitsPerPixel / 8)
        return (0..<3).map { bytes[offset + $0] }
    }

    private func frameImage(
        of film: URL, at seconds: Double, saveAs name: String
    ) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: film))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(
            at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        if let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask).first,
           let data = UIImage(cgImage: image).pngData() {
            try? data.write(to: caches.appendingPathComponent("\(name).png"))
        }
        return image
    }

    private func frame(of film: URL, at seconds: Double, saveAs name: String) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: film))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(
            at: CMTime(seconds: seconds, preferredTimescale: 600)).image

        if let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask).first {
            let out = caches.appendingPathComponent("\(name).png")
            if let data = UIImage(cgImage: image).pngData() {
                try? data.write(to: out)
            }
        }
        return try XCTUnwrap(image.dataProvider?.data as Data?)
    }
}
