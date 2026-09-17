import CoreGraphics
import XCTest

@testable import AISetlog

/// The corner handle and the centre guide, without a view in the way.
final class CaptionGestureMathTests: XCTestCase {

    // MARK: - The corner handle

    func testPullingStraightOutDoublesTheScaleAndDoesNotTurnIt() throws {
        let move = try XCTUnwrap(CaptionGestureMath.cornerDrag(
            centre: CGPoint(x: 100, y: 100),
            start: CGPoint(x: 140, y: 100),
            current: CGPoint(x: 180, y: 100)))
        XCTAssertEqual(move.scale, 2, accuracy: 0.001)
        XCTAssertEqual(move.angleDelta, 0, accuracy: 0.001)
    }

    func testPushingInwardsShrinksIt() throws {
        let move = try XCTUnwrap(CaptionGestureMath.cornerDrag(
            centre: CGPoint(x: 100, y: 100),
            start: CGPoint(x: 140, y: 100),
            current: CGPoint(x: 120, y: 100)))
        XCTAssertEqual(move.scale, 0.5, accuracy: 0.001)
    }

    /// A quarter turn around the centre at the same radius: all angle, no size.
    func testSweepingAroundTurnsItWithoutResizing() throws {
        let move = try XCTUnwrap(CaptionGestureMath.cornerDrag(
            centre: CGPoint(x: 0, y: 0),
            start: CGPoint(x: 40, y: 0),
            current: CGPoint(x: 0, y: 40)))
        XCTAssertEqual(move.scale, 1, accuracy: 0.001)
        XCTAssertEqual(move.angleDelta, 90, accuracy: 0.001)
    }

    /// Crossing the negative x axis is where `atan2` jumps by a full turn:
    /// raw subtraction answers -348.58° for a finger that moved 8pt. Added to a
    /// saved angle that clamps at ±35°, that slams the caption to the stop
    /// instead of nudging it, so the short way round is the only useful answer.
    ///
    /// Positive because y grows downwards here: 4 → -4 at x = -40 sweeps
    /// clockwise on screen, which is the direction `rotationEffect` calls
    /// positive.
    func testCrossingTheAxisReportsTheShortWayRound() throws {
        let move = try XCTUnwrap(CaptionGestureMath.cornerDrag(
            centre: .zero,
            start: CGPoint(x: -40, y: 4),
            current: CGPoint(x: -40, y: -4)))
        XCTAssertEqual(move.angleDelta, 11.42, accuracy: 0.05)
        XCTAssertLessThan(abs(move.angleDelta), 30)
    }

    func testAGestureStartedOnTheCentreIsRefusedRatherThanSpun() {
        XCTAssertNil(CaptionGestureMath.cornerDrag(
            centre: CGPoint(x: 100, y: 100),
            start: CGPoint(x: 103, y: 101),
            current: CGPoint(x: 160, y: 40)))
    }

    // MARK: - The centre guide

    func testNearlyCentredSnapsExactlyToTheMiddle() {
        XCTAssertEqual(CaptionGestureMath.snapToCentre(0.512), 0.5)
        XCTAssertEqual(CaptionGestureMath.snapToCentre(0.489), 0.5)
        XCTAssertEqual(CaptionGestureMath.snapToCentre(0.5), 0.5)
    }

    func testDeliberatelyOffCentreIsLeftAlone() {
        XCTAssertNil(CaptionGestureMath.snapToCentre(0.2))
        XCTAssertNil(CaptionGestureMath.snapToCentre(0.62))
        // Just outside the threshold: the guide must not grab a caption the
        // user is holding a visible distance off the middle.
        XCTAssertNil(CaptionGestureMath.snapToCentre(0.54))
    }

    /// The saved value still goes through `CaptionSticker`, so a snapped
    /// position survives the clamp it passes on the way to the card.
    func testASnappedPositionSurvivesTheStickersOwnClamping() throws {
        let snapped = try XCTUnwrap(CaptionGestureMath.snapToCentre(0.503))
        let sticker = CaptionSticker(x: snapped, y: 0.43, style: .outline)
        XCTAssertEqual(sticker.x, 0.5, accuracy: 0.0001)
    }
}
