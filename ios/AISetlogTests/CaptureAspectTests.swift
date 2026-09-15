import XCTest
@testable import AISetlog

/// The shape the camera films in and the shape the film renders at are one
/// fact. For a while they were two constants: `Challenge.Orientation`
/// framed portrait at `9 / 14.3` while `VideoStitcher.Aspect` rendered `9 / 16`.
///
/// That gap is not cosmetic, because every surface showing a clip aspect-*fills*
/// its box. A box wider than the file crops the top and bottom off and scales
/// up what is left — 12% on the live preview and the review screen, and what
/// sits mid-frame in a 1Day clip is a face. It shipped because nothing here
/// compared the two numbers.
final class CaptureAspectTests: XCTestCase {

    /// Each orientation must frame the camera at the shape its own film
    /// renders at, so aspect-fill has nothing left to crop.
    func testOrientationAspectMatchesTheFilmItRendersAt() {
        let pairs: [(Challenge.Orientation, VideoStitcher.Aspect)] = [
            (.portrait, .portrait),
            (.landscape, .landscape),
            (.square, .square),
        ]

        for (orientation, aspect) in pairs {
            XCTAssertEqual(
                orientation.aspectRatio, aspect.ratio, accuracy: 0.0001,
                """
                \(orientation) frames the camera at \(orientation.aspectRatio) \
                but its film renders at \(aspect.ratio). Any surface that \
                aspect-fills will crop the difference out of the middle of the \
                frame.
                """)
        }
    }

    /// The specific number that caused it, named so a well-meaning layout
    /// tweak can't quietly put it back.
    func testPortraitIsNotTheOldCameraShellShape() {
        XCTAssertNotEqual(
            Challenge.Orientation.portrait.aspectRatio, 9 / 14.3, accuracy: 0.0001,
            "9/14.3 is a layout shape, not a capture shape — it matches no file the camera writes.")
    }

    /// Every case is covered above. A fourth orientation added without a line
    /// in `pairs` would otherwise be silently unchecked.
    func testEveryOrientationIsChecked() {
        XCTAssertEqual(
            Challenge.Orientation.allCases.count, 3,
            "A new orientation needs a row in testOrientationAspectMatchesTheFilmItRendersAt.")
    }
}
