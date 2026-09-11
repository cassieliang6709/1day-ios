import AVFoundation
import UIKit
import XCTest
@testable import AISetlog

/// The shared-room grid must show all of everybody.
///
/// The layout this replaced scaled each take until it covered its cell and cut
/// off whatever hung over the edge, which for a portrait take in a landscape
/// cell is the top and bottom — the head and the hands. These tests film a
/// banded clip so the two ends are a different colour from the middle, and then
/// look for those ends in the finished film. A cropping layout cannot pass them:
/// the blurred bed is a cover-scaled copy of the same take, so it does not
/// contain the bands either.
final class FriendsTogetherCompositorTests: XCTestCase {
    private var owned: [URL] = []

    override func tearDown() {
        owned.forEach { try? FileManager.default.removeItem(at: $0) }
        owned = []
        super.tearDown()
    }

    // MARK: - Orientation

    func testOrientationCoversTheFourRotationsACameraProduces() {
        let cases: [(CGAffineTransform, CGImagePropertyOrientation)] = [
            (.identity, .up),
            (CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 540, ty: 0), .right),
            (CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 960), .left),
            (CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 540, ty: 960), .down),
        ]
        for (transform, expected) in cases {
            XCTAssertEqual(
                FriendsTogetherPlacement.orientation(for: transform), expected,
                "\(transform)")
        }
    }

    func testOrientationToleratesTheNonIntegralTransformsFilesCarry() {
        // A transform read back off a file is rarely exactly integral. The four
        // rotations are 90° apart, so rounding cannot land on the wrong one.
        let almostRight = CGAffineTransform(
            a: 0.0000001, b: 0.9999998, c: -0.9999999, d: 0.0000002, tx: 540, ty: 0)
        XCTAssertEqual(FriendsTogetherPlacement.orientation(for: almostRight), .right)
    }

    // MARK: - No crop

    func testPortraitTakesKeepTheirTopAndBottomInALandscapeFilm() async throws {
        let banded = try await bandedClip()
        let film = try await render([banded, banded], aspect: .landscape)
        let frame = try await sample(film)

        // Cell 0 is the left half of a two-up landscape grid. Down its middle,
        // the ends of the take have to still be there.
        let column = frame.size.width * 0.25
        XCTAssertTrue(
            frame.contains(.red, alongColumn: column, in: 0...0.15),
            "The top of a portrait take was cut off in a landscape cell")
        XCTAssertTrue(
            frame.contains(.blue, alongColumn: column, in: 0.85...1),
            "The bottom of a portrait take was cut off in a landscape cell")
    }

    func testLandscapeTakesKeepTheirEdgesInAPortraitFilm() async throws {
        // Same clip turned on its side: the bands now run down the left and
        // right, and a cover-scaled cell would cut those off instead.
        let banded = try await bandedClip(landscape: true)
        let film = try await render([banded, banded], aspect: .portrait)
        let frame = try await sample(film)

        let row = frame.size.height * 0.25
        XCTAssertTrue(
            frame.contains(.red, alongRow: row, in: 0...0.15),
            "The left edge of a landscape take was cut off in a portrait cell")
        XCTAssertTrue(
            frame.contains(.blue, alongRow: row, in: 0.85...1),
            "The right edge of a landscape take was cut off in a portrait cell")
    }

    func testTheGapBetweenCellsStaysBlackSoNobodyBleedsIntoAnybodyElse() async throws {
        let banded = try await bandedClip()
        let film = try await render([banded, banded], aspect: .landscape)
        let frame = try await sample(film)

        // The seam down the middle of a two-up grid. Both cells are inset, so
        // whatever is there came from the instruction background, not a take
        // that overflowed — the failure the old crop rectangle existed to stop.
        let seam = frame.pixel(x: frame.size.width / 2, y: frame.size.height / 2)
        XCTAssertLessThan(seam.r, 60)
        XCTAssertLessThan(seam.g, 60)
        XCTAssertLessThan(seam.b, 60)
    }

    // MARK: - Fixtures

    /// A clip banded at both ends: red for the first 8%, blue for the last 8%,
    /// green in between.
    ///
    /// 8% is chosen against the cover-scaled bed. For a 9:16 take in a 16:9
    /// half-cell the bed shows the middle ~63%, so neither band is inside it,
    /// and finding one in the film proves it came from the fitted copy.
    private func bandedClip(landscape: Bool = false) async throws -> URL {
        let size = landscape
            ? CGSize(width: 960, height: 540)
            : CGSize(width: 540, height: 960)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("banded-\(UUID().uuidString).mov")
        owned.append(url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: size.width,
                AVVideoHeightKey: size.height,
            ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw Failure.writer }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let buffer = try XCTUnwrap(bandedBuffer(size: size, landscape: landscape))
        for frame in 0..<15 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(
                buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw Failure.writer }
        return url
    }

    private func bandedBuffer(size: CGSize, landscape: Bool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB,
            [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary,
            &buffer)
        guard let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        else { return nil }

        context.setFillColor(UIColor.green.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        // CGContext counts from the bottom, so "first band" is drawn last.
        let band = 0.08
        if landscape {
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size.width * band, height: size.height))
            context.setFillColor(UIColor.blue.cgColor)
            context.fill(CGRect(
                x: size.width * (1 - band), y: 0,
                width: size.width * band, height: size.height))
        } else {
            context.setFillColor(UIColor.blue.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * band))
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(
                x: 0, y: size.height * (1 - band),
                width: size.width, height: size.height * band))
        }
        return buffer
    }

    private func render(
        _ urls: [URL], aspect: VideoStitcher.Aspect
    ) async throws -> URL {
        var options = VideoStitcher.Options()
        options.layout = .friendsTogether
        options.aspect = aspect
        options.showDayCaptions = false
        options.crossfadeSeconds = 0
        let clips = urls.enumerated().map { index, url in
            DayClip(
                day: 1, url: url, authorName: "Sample \(index)",
                authorID: "sample-\(index)", key: "sample-\(index)")
        }
        let film = try await VideoStitcher.stitch(clips: clips, options: options)
        owned.append(film)
        return film
    }

    /// One frame of the finished film, as pixels.
    private func sample(_ film: URL) async throws -> Frame {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: film))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
        let cgImage = try await generator.image(
            at: CMTime(seconds: 0.2, preferredTimescale: 600)).image
        return try XCTUnwrap(Frame(cgImage))
    }

    private enum Failure: Error { case writer }

    // MARK: - Reading pixels

    private struct Frame {
        enum Band { case red, blue }

        let size: CGSize
        private let pixels: [UInt8]
        private let bytesPerRow: Int

        init?(_ image: CGImage) {
            let width = image.width, height = image.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = data.withUnsafeMutableBytes({ raw in
                CGContext(
                    data: raw.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            self.pixels = data
            self.bytesPerRow = width * 4
            self.size = CGSize(width: width, height: height)
        }

        func pixel(x: CGFloat, y: CGFloat) -> (r: Int, g: Int, b: Int) {
            let column = min(max(Int(x), 0), Int(size.width) - 1)
            let row = min(max(Int(y), 0), Int(size.height) - 1)
            let offset = row * bytesPerRow + column * 4
            return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
        }

        /// Whether `band` shows up anywhere in a fraction of one column.
        ///
        /// A range rather than a point: the exact row depends on the cell inset
        /// and the scale, and the claim under test is that the band survived at
        /// all, not where to the pixel it landed.
        func contains(
            _ band: Band, alongColumn x: CGFloat, in range: ClosedRange<CGFloat>
        ) -> Bool {
            let rows = stride(
                from: size.height * range.lowerBound,
                to: size.height * range.upperBound, by: 1)
            return rows.contains { matches(band, pixel(x: x, y: $0)) }
        }

        func contains(
            _ band: Band, alongRow y: CGFloat, in range: ClosedRange<CGFloat>
        ) -> Bool {
            let columns = stride(
                from: size.width * range.lowerBound,
                to: size.width * range.upperBound, by: 1)
            return columns.contains { matches(band, pixel(x: $0, y: y)) }
        }

        /// Dominance rather than equality: the film is H.264, so a pure red
        /// comes back a few values off, and the bed is a dimmed copy. What
        /// separates the bands from the green middle is which channel leads.
        private func matches(_ band: Band, _ pixel: (r: Int, g: Int, b: Int)) -> Bool {
            switch band {
            case .red: pixel.r > pixel.g + 40 && pixel.r > pixel.b + 40
            case .blue: pixel.b > pixel.g + 40 && pixel.b > pixel.r + 40
            }
        }
    }
}
