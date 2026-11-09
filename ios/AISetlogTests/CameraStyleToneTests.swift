import XCTest
@testable import AISetlog

/// Pins the no-grey decision: a camera is its frame and date, plus at most a
/// slight warmth on film. Lifting exposure or flattening contrast is what made
/// every take look washed out.
final class CameraStyleToneTests: XCTestCase {
    func testCamcorderAndInstantBakeNoTone() {
        XCTAssertTrue(CameraStyle.camcorder.tone.isIdentity)
        XCTAssertTrue(CameraStyle.instant.tone.isIdentity)
        XCTAssertTrue(CameraStyle.standard.tone.isIdentity)
    }

    func testFilmIsWarmthOnly() {
        let tone = CameraStyle.film.tone
        XCTAssertGreaterThan(tone.temperature, 0)
        XCTAssertLessThanOrEqual(tone.temperature, 15)
        XCTAssertEqual(tone.exposure, 0)
        XCTAssertEqual(tone.contrast, 0)
    }

    func testOnlyFilmWashesThePreview() {
        XCTAssertEqual(CameraStyle.camcorder.previewWash.opacity, 0)
        XCTAssertEqual(CameraStyle.instant.previewWash.opacity, 0)
        XCTAssertLessThanOrEqual(CameraStyle.film.previewWash.opacity, 0.08)
    }

    func testInstantCardIsOpaque() throws {
        let image = try XCTUnwrap(CameraStyle.instant.overlay(
            size: CGSize(width: 300, height: 400), date: Date(timeIntervalSince1970: 0)))
        let cg = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Top-left corner of the card: border, must be fully opaque.
        context.draw(cg, in: CGRect(x: 0, y: -399, width: 300, height: 400))
        XCTAssertEqual(pixel[3], 255)
    }
}
