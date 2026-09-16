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
        await model.prepare(count: 2, landscape: false, chinese: true)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.clips.count, 3)
        var urls = model.clips.map(\.url)
        urls.append(try XCTUnwrap(model.film))
        await model.prepare(count: 3, landscape: true, chinese: true)
        XCTAssertFalse(model.failed)
        urls.append(try XCTUnwrap(model.film))
        for url in urls {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let first = try await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image
            let later = try await generator.image(at: CMTime(seconds: 2.5, preferredTimescale: 600)).image
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
