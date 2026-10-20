import CoreGraphics
import XCTest
@testable import AISetlog

/// The avatar spec's red lines (§3.4), held by the decoration layer, which is
/// ours whatever made the head: two or three stickers and never more, none on
/// a cheek, two blushes where the face's cheeks are, a rainbow outline that
/// stays inside the transparent margin.
final class AvatarDecorLayoutTests: XCTestCase {
    private let face = CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.6)

    private func layout(seed: UInt64, face: CGRect? = nil, cheeks: [CGPoint]? = nil,
                        headSize: CGSize = CGSize(width: 600, height: 700)) -> AvatarDecorLayout {
        AvatarDecorLayout.make(canvas: 768, headSize: headSize,
                               face: face ?? self.face, cheeks: cheeks, seed: seed)
    }

    func testTwoOrThreeStickersForAnySeed() {
        var counts: Set<Int> = []
        for seed in UInt64(1)...300 {
            let n = layout(seed: seed).stickers.count
            XCTAssertTrue((2...3).contains(n), "seed \(seed) drew \(n) stickers")
            counts.insert(n)
        }
        XCTAssertEqual(counts, [2, 3], "both two and three should come up")
    }

    func testStickersStayOffTheCheeksAndOffEachOther() {
        for seed in UInt64(1)...300 {
            let l = layout(seed: seed)
            for s in l.stickers {
                for c in l.cheeks {
                    XCTAssertGreaterThan(
                        hypot(s.center.x - c.center.x, s.center.y - c.center.y),
                        c.radius.width + s.size / 2, "seed \(seed): sticker on a cheek")
                }
            }
            for (i, a) in l.stickers.enumerated() {
                for b in l.stickers[(i + 1)...] {
                    XCTAssertGreaterThan(hypot(a.center.x - b.center.x, a.center.y - b.center.y),
                                         (a.size + b.size) / 2, "seed \(seed): stickers overlap")
                }
            }
        }
    }

    func testNothingIsDrawnInTheSafeMargin() {
        for seed in UInt64(1)...100 {
            let l = layout(seed: seed)
            let safe = CGRect(x: l.safeMargin, y: l.safeMargin,
                              width: l.canvas - 2 * l.safeMargin, height: l.canvas - 2 * l.safeMargin)
            let outline = l.headRect.insetBy(dx: -l.outlineReach, dy: -l.outlineReach)
            XCTAssertTrue(safe.contains(outline.integral.insetBy(dx: 1, dy: 1)),
                          "seed \(seed): outline \(outline) leaves \(safe)")
            for s in l.stickers {
                let box = CGRect(x: s.center.x - s.size / 2, y: s.center.y - s.size / 2,
                                 width: s.size, height: s.size)
                XCTAssertTrue(safe.contains(box.insetBy(dx: 0.5, dy: 0.5)), "seed \(seed): sticker \(box)")
            }
        }
    }

    func testBlushGoesWhereTheLandmarksSayTheCheeksAre() {
        let hints = [CGPoint(x: 0.3, y: 0.7), CGPoint(x: 0.7, y: 0.7)]
        let l = layout(seed: 7, cheeks: hints)
        XCTAssertEqual(l.cheeks.count, 2)
        for (cheek, hint) in zip(l.cheeks, hints) {
            XCTAssertEqual(cheek.center.x, l.headRect.minX + hint.x * l.headRect.width, accuracy: 0.001)
            XCTAssertEqual(cheek.center.y, l.headRect.minY + hint.y * l.headRect.height, accuracy: 0.001)
        }
    }

    func testWithoutLandmarksBlushSitsLowOnTheFaceOneEachSide() {
        let l = layout(seed: 7)
        let faceRect = CGRect(x: l.headRect.minX + face.minX * l.headRect.width,
                              y: l.headRect.minY + face.minY * l.headRect.height,
                              width: face.width * l.headRect.width, height: face.height * l.headRect.height)
        XCTAssertEqual(l.cheeks.count, 2)
        XCTAssertLessThan(l.cheeks[0].center.x, faceRect.midX)
        XCTAssertGreaterThan(l.cheeks[1].center.x, faceRect.midX)
        for c in l.cheeks {
            XCTAssertTrue(faceRect.contains(c.center))
            XCTAssertGreaterThan(c.center.y, faceRect.midY, "blush belongs below the eyes")
        }
    }

    func testOutlineIsSixRainbowBandsOutsideOneWhiteBand() {
        let l = layout(seed: 3)
        XCTAssertEqual(l.bands.map(\.color), AvatarDecorLayout.rainbow + [AvatarDecorLayout.white])
        let reaches = l.bands.map(\.reach)
        XCTAssertEqual(reaches, reaches.sorted(by: >), "painted outermost first")
        // Every band goes all the way round.
        for band in l.bands { XCTAssertEqual(band.offsets.count, AvatarDecorLayout.samples) }
    }

    func testTheRainbowWobblesButOnlyALittle() {
        let l = layout(seed: 11)
        let bandWidth = l.canvas * 0.016
        for band in l.bands.dropLast() {
            let radii = band.offsets.map { hypot($0.x, $0.y) }
            XCTAssertGreaterThan(radii.max()! - radii.min()!, 0.5, "a ruled line, not crayon")
            for r in radii {
                XCTAssertLessThanOrEqual(abs(r - band.reach), bandWidth * AvatarDecorLayout.wobble + 0.001)
            }
        }
        // The white band is the even edge next to the face.
        let white = l.bands.last!.offsets.map { hypot($0.x, $0.y) }
        XCTAssertEqual(white.max()!, white.min()!, accuracy: 0.001)
    }

    func testTheSameSeedDrawsTheSameAvatarAndANewSeedDoesNot() {
        XCTAssertEqual(layout(seed: 42), layout(seed: 42))
        XCTAssertNotEqual(layout(seed: 42).stickers, layout(seed: 43).stickers)
    }

    func testAHeadWithNoFaceStillGetsBlushAndStickers() {
        let l = AvatarDecorLayout.make(canvas: 768, headSize: CGSize(width: 500, height: 500),
                                       face: nil, cheeks: nil, seed: 5)
        XCTAssertEqual(l.cheeks.count, 2)
        XCTAssertTrue((2...3).contains(l.stickers.count))
        XCTAssertTrue(l.headRect.contains(l.cheeks[0].center))
    }

    func testTheHeadIsCentredAndKeepsItsShape() {
        let l = layout(seed: 1, headSize: CGSize(width: 600, height: 700))
        XCTAssertEqual(l.headRect.midX, 384, accuracy: 0.001)
        XCTAssertEqual(l.headRect.midY, 384, accuracy: 0.001)
        XCTAssertEqual(l.headRect.width / l.headRect.height, 600.0 / 700.0, accuracy: 0.001)
    }

    // MARK: - Rendering

    func testTheRenderedAvatarIsSquareWithClearCornersAndAFilledMiddle() throws {
        let head = try XCTUnwrap(Self.disc(side: 400))
        let l = AvatarDecorLayout.make(canvas: 256, headSize: CGSize(width: 400, height: 400),
                                       face: nil, cheeks: nil, seed: 9)
        let image = try XCTUnwrap(AvatarDecorator.render(head: head, layout: l))
        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(image.height, 256)
        let alpha = Self.alpha(of: image)
        XCTAssertEqual(alpha(2, 2), 0, "the margin is transparent")
        XCTAssertEqual(alpha(253, 253), 0)
        XCTAssertEqual(alpha(128, 128), 255, "the face is opaque")
        // Just outside the head, the outline has painted something.
        let edge = Int(l.headRect.maxX + l.bands.last!.reach / 2)
        XCTAssertGreaterThan(alpha(edge, 128), 200)
    }

    func testProgressZeroIsTheBareHead() throws {
        let head = try XCTUnwrap(Self.disc(side: 400))
        let l = AvatarDecorLayout.make(canvas: 256, headSize: CGSize(width: 400, height: 400),
                                       face: nil, cheeks: nil, seed: 9)
        let bare = try XCTUnwrap(AvatarDecorator.render(head: head, layout: l, progress: 0))
        let edge = Int(l.headRect.maxX + l.bands.last!.reach / 2)
        XCTAssertEqual(Self.alpha(of: bare)(edge, 128), 0, "no outline yet")
    }

    private static func disc(side: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.7, blue: 0.6, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()
    }

    /// Alpha at (x, y), top-left origin.
    private static func alpha(of image: CGImage) -> (Int, Int) -> UInt8 {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Bitmap memory is top row first.
        return { x, y in pixels[(y * w + x) * 4 + 3] }
    }
}
