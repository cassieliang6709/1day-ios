import XCTest
import AVFoundation
import CoreGraphics
@testable import AISetlog

/// File-level evidence only: these assertions do not prove AVPlayer renders
/// on a physical device. Keep the device black-screen issue open until E4.
@MainActor
final class RoomVideoDemoFrameTests: XCTestCase {
    func testGeneratedSourcesAndTogetherFilmsContainVisibleMovingFrames() async throws {
        let model = RoomVideoDemoModel()
        defer { model.close() }
        await model.prepare(count: 2, landscape: false, chinese: true, clipSeconds: DemoHarness.clipSeconds)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.clips.count, 3)
        var urls = model.clips.map(\.url)
        urls.append(try XCTUnwrap(model.film))
        await model.prepare(count: 3, landscape: true, chinese: true, clipSeconds: DemoHarness.clipSeconds)
        XCTAssertFalse(model.failed)
        urls.append(try XCTUnwrap(model.film))
        for url in urls {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            // Near the start and near the end, in the clip's own terms. These
            // used to be 0.2s and 2.5s, which silently required the stand-in
            // generator to keep producing three-second clips — a fact this
            // test is not about, and the one that broke when it changed.
            let duration = try await asset.load(.duration).seconds
            let first = try await generator.image(
                at: CMTime(seconds: duration * 0.1, preferredTimescale: 600)).image
            let later = try await generator.image(
                at: CMTime(seconds: duration * 0.9, preferredTimescale: 600)).image
            let a = try pixels(first)
            let b = try pixels(later)
            let count = a.count / 4
            let visible = (0..<count).filter { i in
                max(a[i * 4], a[i * 4 + 1], a[i * 4 + 2]) > 40
            }.count
            let changed = (0..<count).filter { i in
                (0..<3).contains { channel in
                    abs(Int(a[i * 4 + channel]) - Int(b[i * 4 + channel])) > 12
                }
            }.count
            XCTAssertGreaterThan(visible, count / 2, "Mostly black: \(url.lastPathComponent)")
            XCTAssertGreaterThan(changed, 5, "No visible motion: \(url.lastPathComponent)")
        }
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let width = 96, height = 96
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }
}
