import XCTest
@testable import AISetlog

final class CameraZoomTests: XCTestCase {

    private let triple = CameraZoom(base: 2, minFactor: 1, maxFactor: 123)
    private let front = CameraZoom(base: 1, minFactor: 1, maxFactor: 5)


    func testWideBaseIsTheSwitchOverFactorBeforeTheWideLens() {
        XCTAssertEqual(CameraZoom.wideBase(wideIndex: 1, switchOverFactors: [2, 6]), 2)
    }

    func testWideBaseIsOneWhenTheWideLensIsTheWidest() {
        XCTAssertEqual(CameraZoom.wideBase(wideIndex: 0, switchOverFactors: [2]), 1)
    }

    func testWideBaseIsOneForASingleLensDevice() {
        XCTAssertEqual(CameraZoom.wideBase(wideIndex: nil, switchOverFactors: []), 1)
    }

    func testWideBaseIsOneWhenTheFactorsAreMissing() {
        XCTAssertEqual(CameraZoom.wideBase(wideIndex: 2, switchOverFactors: [2]), 1)
    }


    func testHalfXIsTheWidestLens() {
        XCTAssertEqual(triple.factor(forDisplay: 0.5), 1, accuracy: 0.0001)
    }

    func testOneXIsTheWideLensesSwitchOverPoint() {
        XCTAssertEqual(triple.factor(forDisplay: 1), 2, accuracy: 0.0001)
        XCTAssertEqual(triple.factor(forDisplay: 2), 4, accuracy: 0.0001)
    }

    func testFactorAndDisplayRoundTrip() {
        for display: CGFloat in [0.5, 1, 1.8, 2, 7] {
            XCTAssertEqual(
                triple.display(forFactor: triple.factor(forDisplay: display)),
                display,
                accuracy: 0.0001)
        }
    }

    func testDisplayIsTheFactorItselfWhenThereIsNoUltraWide() {
        XCTAssertEqual(front.factor(forDisplay: 2), 2, accuracy: 0.0001)
    }


    func testZoomBelowTheLensIsClampedToItsWidest() {
        XCTAssertEqual(triple.clampedDisplay(0.1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(front.clampedDisplay(0.5), 1, accuracy: 0.0001)
    }

    func testZoomIsCappedBelowTheHardwareCeiling() {
        XCTAssertEqual(triple.maxDisplay, CameraZoom.interactiveCeiling, accuracy: 0.0001)
        XCTAssertEqual(triple.clampedDisplay(99), CameraZoom.interactiveCeiling, accuracy: 0.0001)
    }

    func testShortHardwareRangeCapsBelowTheCeiling() {
        XCTAssertEqual(front.maxDisplay, 5, accuracy: 0.0001)
        XCTAssertEqual(front.clampedDisplay(9), 5, accuracy: 0.0001)
    }

    func testNonFiniteZoomFallsBackToOneX() {
        XCTAssertEqual(triple.clampedDisplay(.nan), 1, accuracy: 0.0001)
        XCTAssertEqual(triple.clampedDisplay(.infinity), 1, accuracy: 0.0001)
    }


    func testBackCameraOffersAllThreeChips() {
        XCTAssertEqual(triple.presets(), [0.5, 1, 2])
    }

    func testFrontCameraDropsTheHalfXChip() {
        XCTAssertEqual(front.presets(), [1, 2])
    }

    func testAMinimumOfExactlyHalfXKeepsItsChip() {
        let fuzzy = CameraZoom(base: 2.0000001, minFactor: 1, maxFactor: 20)
        XCTAssertEqual(fuzzy.presets().first, 0.5)
    }

    func testASingleLensCameraOffersOneChipSoTheUIDrawsNone() {
        XCTAssertEqual(CameraZoom.unavailable.presets(), [1])
    }

    func testPresetsNeverComeBackEmpty() {
        let telephotoOnly = CameraZoom(base: 1, minFactor: 3, maxFactor: 6)
        XCTAssertEqual(telephotoOnly.presets(), [3])
    }


    func testLabelsDropTheDecimalWhenItIsAZero() {
        XCTAssertEqual(CameraZoom.label(1), "1x")
        XCTAssertEqual(CameraZoom.label(2), "2x")
        XCTAssertEqual(CameraZoom.label(10), "10x")
    }

    func testLabelsKeepOneDecimalWhenThereIsOne() {
        XCTAssertEqual(CameraZoom.label(0.5), "0.5x")
        XCTAssertEqual(CameraZoom.label(1.75), "1.8x")
        XCTAssertEqual(CameraZoom.label(2.34), "2.3x")
    }

    func testMatchToleranceRecognisesAClampedPreset() {
        XCTAssertTrue(CameraZoom.isSame(triple.clampedDisplay(0.5), 0.5))
        XCTAssertFalse(CameraZoom.isSame(1, 2))
    }


    func testAZeroBaseCannotDivideEveryDisplayValueByNothing() {
        let broken = CameraZoom(base: 0, minFactor: 1, maxFactor: 4)
        XCTAssertEqual(broken.base, 1)
        XCTAssertEqual(broken.factor(forDisplay: 2), 2, accuracy: 0.0001)
    }
}

extension CameraZoomTests {
    func testAStationaryDragDoesNotMoveTheLens() {
        XCTAssertEqual(CameraZoom.zoom(draggedBy: 0, from: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(CameraZoom.zoom(draggedBy: 0, from: 2.7), 2.7, accuracy: 0.0001)
    }

    func testTheSameTravelAlwaysDoublesOrHalves() {
        let travel = CameraZoom.pointsPerDoubling
        for start in [CGFloat(0.5), 1, 2, 4.3] {
            XCTAssertEqual(
                CameraZoom.zoom(draggedBy: travel, from: start), start * 2,
                accuracy: 0.001,
                "dragging one doubling from \(start) should double it")
            XCTAssertEqual(
                CameraZoom.zoom(draggedBy: -travel, from: start), start / 2,
                accuracy: 0.001,
                "dragging back should halve it")
        }
    }

    func testDraggingRightZoomsInAndLeftZoomsOut() {
        XCTAssertGreaterThan(CameraZoom.zoom(draggedBy: 40, from: 1), 1)
        XCTAssertLessThan(CameraZoom.zoom(draggedBy: -40, from: 1), 1)
    }

    func testTheMappingDoesNotClampAndLeavesThatToTheRecorder() {
        let huge = CameraZoom.zoom(draggedBy: 2000, from: 1)
        XCTAssertGreaterThan(huge, CameraZoom.interactiveCeiling)
    }
}
