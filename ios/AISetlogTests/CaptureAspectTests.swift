import XCTest
@testable import AISetlog

final class CaptureAspectTests: XCTestCase {

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

    func testPortraitIsNotTheOldCameraShellShape() {
        XCTAssertNotEqual(
            Challenge.Orientation.portrait.aspectRatio, 9 / 14.3, accuracy: 0.0001,
            "9/14.3 is a layout shape, not a capture shape — it matches no file the camera writes.")
    }

    func testEveryOrientationIsChecked() {
        XCTAssertEqual(
            Challenge.Orientation.allCases.count, 3,
            "A new orientation needs a row in testOrientationAspectMatchesTheFilmItRendersAt.")
    }
}
