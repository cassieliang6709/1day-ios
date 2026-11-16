import AVFoundation
import UIKit
import XCTest
@testable import AISetlog

final class FriendsTogetherCompositorTests: XCTestCase {
    private var owned: [URL] = []

    override func tearDown() {
        owned.forEach { try? FileManager.default.removeItem(at: $0) }
        owned = []
        super.tearDown()
    }


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
        let almostRight = CGAffineTransform(
            a: 0.0000001, b: 0.9999998, c: -0.9999999, d: 0.0000002, tx: 540, ty: 0)
        XCTAssertEqual(FriendsTogetherPlacement.orientation(for: almostRight), .right)
    }


    func testPortraitTakesKeepTheirTopAndBottomInALandscapeFilm() async throws {
        let banded = try await bandedClip()
        let film = try await render([banded, banded], aspect: .landscape)
        let frame = try await sample(film)

        let column = frame.size.width * 0.25
        XCTAssertTrue(
            frame.contains(.red, alongColumn: column, in: 0...0.15),
            "The top of a portrait take was cut off in a landscape cell")
        XCTAssertTrue(
            frame.contains(.blue, alongColumn: column, in: 0.85...1),
            "The bottom of a portrait take was cut off in a landscape cell")
    }

    func testLandscapeTakesKeepTheirEdgesInAPortraitFilm() async throws {
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

    func testTwoPortraitTakesFillTheAutomaticCanvasWholeAndUncropped() async throws {
        let banded = try await bandedClip()
        let film = try await render([banded, banded])
        let frame = try await sample(film)

        XCTAssertEqual(frame.size.width / frame.size.height, 9.0 / 8, accuracy: 0.02)
        for column in [frame.size.width * 0.25, frame.size.width * 0.75] {
            XCTAssertTrue(
                frame.contains(.red, alongColumn: column, in: 0...0.04),
                "the top of a take is missing from the automatic canvas")
            XCTAssertTrue(
                frame.contains(.blue, alongColumn: column, in: 0.96...1),
                "the bottom of a take is missing from the automatic canvas")
        }
    }

    func testCellsMeetWithNoBarDownTheSeam() async throws {
        let banded = try await bandedClip()
        let film = try await render([banded, banded])
        let frame = try await sample(film)

        let middle = frame.size.height / 2
        for offset in -2...2 {
            let seam = frame.pixel(x: frame.size.width / 2 + CGFloat(offset), y: middle)
            XCTAssertGreaterThan(
                seam.g, 100, "a dark seam at x offset \(offset) down the middle of the film")
        }
    }


    func testLandscapeTakeKeepsItsEdgesInAPortraitDiary() async throws {
        let portrait = try await bandedClip()
        let landscape = try await bandedClip(landscape: true)
        let film = try await render([portrait, landscape], layout: .sequential)

        let first = try await sample(film, at: 0.2)
        XCTAssertEqual(first.size.width / first.size.height, 9.0 / 16, accuracy: 0.02)
        let column = first.size.width / 2
        XCTAssertTrue(
            first.contains(.red, alongColumn: column, in: 0...0.04),
            "a take of the canvas's shape no longer fills it")
        XCTAssertTrue(
            first.contains(.blue, alongColumn: column, in: 0.96...1),
            "a take of the canvas's shape no longer fills it")

        let second = try await sample(film, at: 0.7)
        let middle = second.size.height / 2
        XCTAssertTrue(
            second.contains(.red, alongRow: middle, in: 0...0.15),
            "the left edge of a landscape take was cut off in a portrait diary")
        XCTAssertTrue(
            second.contains(.blue, alongRow: middle, in: 0.85...1),
            "the right edge of a landscape take was cut off in a portrait diary")
        let above = second.pixel(x: second.size.width / 2, y: second.size.height * 0.1)
        XCTAssertGreaterThan(above.g, 100, "black above a fitted take: \(above)")
    }


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
        _ urls: [URL], aspect: VideoStitcher.Aspect? = nil,
        layout: VideoStitcher.Layout = .friendsTogether
    ) async throws -> URL {
        var options = VideoStitcher.Options()
        options.layout = layout
        options.aspect = aspect
        options.showDayCaptions = false
        options.crossfadeSeconds = 0
        let sequential = layout == .sequential
        let clips = urls.enumerated().map { index, url in
            DayClip(
                day: sequential ? index + 1 : 1, url: url, authorName: "Sample \(index)",
                authorID: "sample-\(index)", key: "sample-\(index)")
        }
        let film = try await VideoStitcher.stitch(clips: clips, options: options)
        owned.append(film)
        return film
    }

    private func sample(_ film: URL, at seconds: Double = 0.2) async throws -> Frame {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: film))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
        let cgImage = try await generator.image(
            at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        return try XCTUnwrap(Frame(cgImage))
    }

    private enum Failure: Error { case writer }


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

        private func matches(_ band: Band, _ pixel: (r: Int, g: Int, b: Int)) -> Bool {
            switch band {
            case .red: pixel.r > pixel.g + 40 && pixel.r > pixel.b + 40
            case .blue: pixel.b > pixel.g + 40 && pixel.b > pixel.r + 40
            }
        }
    }
}
