import XCTest
import CoreGraphics
@testable import AISetlog

/// The dual-camera inset's geometry — the numbers the viewfinder and the
/// composed file both read, so a drift here is a preview that lies.
final class PiPInsetTests: XCTestCase {
    private let phone = CGSize(width: 360, height: 640)
    private let file = CGSize(width: 1080, height: 1920)

    func testDefaultSitsTopRightAtThirtyPercent() {
        let rect = PiPInsetLayout.defaultRect()
        XCTAssertEqual(rect.width, 0.3, accuracy: 1e-9)
        XCTAssertEqual(rect.maxX, 1 - PiPInsetLayout.marginShare, accuracy: 1e-9)
        XCTAssertEqual(PiPInsetLayout.clamped(rect), rect)
    }

    func testSizeIsClampedBetween22And45Percent() {
        let tiny = PiPInsetLayout.clamped(CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05))
        XCTAssertEqual(tiny.width, PiPInsetLayout.minShare, accuracy: 1e-9)
        let huge = PiPInsetLayout.clamped(CGRect(x: 0.1, y: 0.1, width: 0.9, height: 0.9))
        XCTAssertEqual(huge.width, PiPInsetLayout.maxShare, accuracy: 1e-9)
    }

    func testRectStaysInsideFrameAndKeepsCanvasShape() {
        for rect in [
            CGRect(x: -0.5, y: -0.2, width: 0.3, height: 0.1),
            CGRect(x: 0.9, y: 0.95, width: 0.4, height: 0.4),
        ] {
            let clamped = PiPInsetLayout.clamped(rect)
            XCTAssertGreaterThanOrEqual(clamped.minX, 0)
            XCTAssertGreaterThanOrEqual(clamped.minY, 0)
            XCTAssertLessThanOrEqual(clamped.maxX, 1 + 1e-9)
            XCTAssertLessThanOrEqual(clamped.maxY, 1 + 1e-9)
            XCTAssertEqual(clamped.width, clamped.height, accuracy: 1e-9)
        }
    }

    func testNonFiniteFallsBackToDefault() {
        let bad = CGRect(x: CGFloat.nan, y: 0, width: 0.3, height: 0.3)
        XCTAssertEqual(PiPInsetLayout.clamped(bad), PiPInsetLayout.defaultRect())
    }

    func testDragMovesByPointsAndStopsAtTheEdge() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        let moved = PiPInsetLayout.moved(start, by: CGSize(width: 36, height: 64), in: phone)
        XCTAssertEqual(moved.minX, 0.3, accuracy: 1e-9)
        XCTAssertEqual(moved.minY, 0.3, accuracy: 1e-9)
        let flung = PiPInsetLayout.moved(start, by: CGSize(width: -999, height: 9999), in: phone)
        XCTAssertEqual(flung.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(flung.maxY, 1, accuracy: 1e-9)
    }

    func testPinchResizesAroundCentreWithinLimits() {
        let start = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        let grown = PiPInsetLayout.resized(start, by: 1.2)
        XCTAssertEqual(grown.width, 0.36, accuracy: 1e-9)
        XCTAssertEqual(grown.midX, start.midX, accuracy: 1e-9)
        XCTAssertEqual(PiPInsetLayout.resized(start, by: 10).width, PiPInsetLayout.maxShare, accuracy: 1e-9)
        XCTAssertEqual(PiPInsetLayout.resized(start, by: 0.1).width, PiPInsetLayout.minShare, accuracy: 1e-9)
    }

    /// A drag in flight is always start + the fingers' total translation.
    /// Fed a finger moving steadily across the stage, the inset moves the
    /// same points per update and never steps back — the jitter was the
    /// translation being read in the moving inset's own space instead.
    func testDragInFlightIsStartPlusTranslationAndNeverStepsBack() {
        let start = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        var lastX = PiPInsetLayout.box(start, in: phone).minX
        for step in 1...10 {
            let translation = CGSize(width: CGFloat(step) * 10, height: CGFloat(step) * 5)
            let rect = PiPInsetLayout.adjusted(start, scale: 1, translation: translation, in: phone)
            let box = PiPInsetLayout.box(rect, in: phone)
            XCTAssertEqual(box.minX - lastX, 10, accuracy: 1e-6)
            XCTAssertEqual(box.minY, start.minY * phone.height + translation.height, accuracy: 1e-6)
            lastX = box.minX
        }
        // Same total translation, same rect, however many updates came first.
        let oneShot = PiPInsetLayout.adjusted(
            start, scale: 1, translation: CGSize(width: 100, height: 50), in: phone)
        XCTAssertEqual(PiPInsetLayout.box(oneShot, in: phone).minX, lastX, accuracy: 1e-6)
    }

    /// Pinch and drag together: grown around the start rect's centre, then
    /// moved, both measured from where the fingers went down.
    func testPinchAndDragTogetherShareOneStartRect() {
        let start = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        let rect = PiPInsetLayout.adjusted(
            start, scale: 1.2, translation: CGSize(width: 36, height: -64), in: phone)
        XCTAssertEqual(rect.width, 0.36, accuracy: 1e-9)
        XCTAssertEqual(rect.midX, start.midX + 0.1, accuracy: 1e-9)
        XCTAssertEqual(rect.midY, start.midY - 0.1, accuracy: 1e-9)
        let still = PiPInsetLayout.adjusted(start, scale: 1, translation: .zero, in: phone)
        XCTAssertEqual(still.minX, start.minX, accuracy: 1e-9)
        XCTAssertEqual(still.minY, start.minY, accuracy: 1e-9)
    }

    /// Preview and file are different sizes; the same normalized rect has to
    /// land on the same proportion of each.
    func testPreviewAndFileBoxesAreTheSameProportion() {
        let rect = CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.4)
        let preview = PiPInsetLayout.box(rect, in: phone)
        let export = PiPInsetLayout.box(rect, in: file)
        XCTAssertEqual(preview.minX / phone.width, export.minX / file.width, accuracy: 1e-9)
        XCTAssertEqual(preview.height / phone.height, export.height / file.height, accuracy: 1e-9)
        XCTAssertEqual(PiPInsetLayout.border(in: phone) / phone.width,
                       PiPInsetLayout.border(in: file) / file.width, accuracy: 1e-9)
    }

    func testBorderIsAboutFourPointsOnAPhone() {
        XCTAssertEqual(PiPInsetLayout.border(in: phone), 4, accuracy: 0.5)
    }

    /// The exported picture is a plain rectangle under the ring. Its corners
    /// stay hidden only while the inner radius (outer minus border) is at
    /// most (1 + √2) × border.
    func testCornerRadiusKeepsSquareVideoCornersUnderTheRing() {
        let inner = PiPInsetLayout.cornerShare - PiPInsetLayout.borderShare
        XCTAssertLessThanOrEqual(inner / PiPInsetLayout.borderShare, 1 + 2.squareRoot())
    }

    func testComposerPictureBoxIsEvenAndInsideTheBorder() {
        let rect = PiPInsetLayout.defaultRect()
        let box = PiPComposer.pictureBox(rect, in: file)
        let outer = PiPInsetLayout.box(rect, in: file)
        XCTAssertEqual(box.width.truncatingRemainder(dividingBy: 2), 0)
        XCTAssertEqual(box.height.truncatingRemainder(dividingBy: 2), 0)
        XCTAssertTrue(outer.contains(box))
    }

    func testPersistenceRoundTripsAndClamps() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PiPInsetTests"))
        defaults.removePersistentDomain(forName: "PiPInsetTests")
        XCTAssertEqual(PiPInsetLayout.load(from: defaults), PiPInsetLayout.defaultRect())

        let rect = CGRect(x: 0.05, y: 0.6, width: 0.4, height: 0.4)
        PiPInsetLayout.save(rect, to: defaults)
        let loaded = PiPInsetLayout.load(from: defaults)
        XCTAssertEqual(loaded.minX, rect.minX, accuracy: 1e-9)
        XCTAssertEqual(loaded.minY, rect.minY, accuracy: 1e-9)
        XCTAssertEqual(loaded.width, rect.width, accuracy: 1e-9)

        defaults.set([0.9, 0.9, 0.9, 0.9], forKey: PiPInsetLayout.storageKey)
        XCTAssertEqual(PiPInsetLayout.load(from: defaults).width, PiPInsetLayout.maxShare, accuracy: 1e-9)
        defaults.removePersistentDomain(forName: "PiPInsetTests")
    }
}
