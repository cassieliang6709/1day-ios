import XCTest
@testable import AISetlog

/// The arithmetic behind the 0.5x / 1x / 2x chips.
///
/// All of it is here rather than on a device because the one number that
/// matters — which `videoZoomFactor` counts as "1x" — is read off the lens
/// stack and is *not* 1.0 on any phone with an ultra-wide camera. Getting it
/// wrong is silent: every chip still works, each one just shows a different
/// picture than it claims to.
final class CameraZoomTests: XCTestCase {

    /// A modern back camera: ultra-wide, wide, telephoto behind one virtual
    /// device, handing over at 2x and 6x.
    private let triple = CameraZoom(base: 2, minFactor: 1, maxFactor: 123)
    /// A front camera: one lens, no ultra-wide, so 1x is the widest it goes.
    private let front = CameraZoom(base: 1, minFactor: 1, maxFactor: 5)

    // MARK: Which factor is 1x

    func testWideBaseIsTheSwitchOverFactorBeforeTheWideLens() {
        // [ultraWide, wide, tele] switching at [2, 6] — the wide lens is
        // constituent 1, so it takes over at 2.0 and that is 1x.
        XCTAssertEqual(CameraZoom.wideBase(wideIndex: 1, switchOverFactors: [2, 6]), 2)
    }

    /// The case that makes reading `switchOverFactors.first` wrong: on a
    /// wide + telephoto phone the only switch-over factor belongs to the
    /// telephoto, and taking it as the base would label real 1x as 0.5x.
    func testWideBaseIsOneWhenTheWideLensIsTheWidest() {
        XCTAssertEqual(CameraZoom.wideBase(wideIndex: 0, switchOverFactors: [2]), 1)
    }

    func testWideBaseIsOneForASingleLensDevice() {
        XCTAssertEqual(CameraZoom.wideBase(wideIndex: nil, switchOverFactors: []), 1)
    }

    /// A constituent list and a switch-over list that disagree in length
    /// should fall back, not read off the end.
    func testWideBaseIsOneWhenTheFactorsAreMissing() {
        XCTAssertEqual(CameraZoom.wideBase(wideIndex: 2, switchOverFactors: [2]), 1)
    }

    // MARK: Display ↔ factor

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

    // MARK: Clamping

    func testZoomBelowTheLensIsClampedToItsWidest() {
        XCTAssertEqual(triple.clampedDisplay(0.1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(front.clampedDisplay(0.5), 1, accuracy: 0.0001)
    }

    /// The hardware reaches 61.5x here. The pinch stops well short of that:
    /// past the telephoto it is all digital crop, and a gesture that can fling
    /// to 60x is a gesture that gets there by accident.
    func testZoomIsCappedBelowTheHardwareCeiling() {
        XCTAssertEqual(triple.maxDisplay, CameraZoom.interactiveCeiling, accuracy: 0.0001)
        XCTAssertEqual(triple.clampedDisplay(99), CameraZoom.interactiveCeiling, accuracy: 0.0001)
    }

    func testShortHardwareRangeCapsBelowTheCeiling() {
        XCTAssertEqual(front.maxDisplay, 5, accuracy: 0.0001)
        XCTAssertEqual(front.clampedDisplay(9), 5, accuracy: 0.0001)
    }

    /// A pinch multiplying into a NaN must not leave the lens somewhere
    /// unrepresentable.
    func testNonFiniteZoomFallsBackToOneX() {
        XCTAssertEqual(triple.clampedDisplay(.nan), 1, accuracy: 0.0001)
        XCTAssertEqual(triple.clampedDisplay(.infinity), 1, accuracy: 0.0001)
    }

    // MARK: Presets

    func testBackCameraOffersAllThreeChips() {
        XCTAssertEqual(triple.presets(), [0.5, 1, 2])
    }

    /// The chip has to disappear rather than clamp: a 0.5x button on a front
    /// camera would quietly show the 1x picture and claim otherwise.
    func testFrontCameraDropsTheHalfXChip() {
        XCTAssertEqual(front.presets(), [1, 2])
    }

    func testAMinimumOfExactlyHalfXKeepsItsChip() {
        // 1.0 / 2.0 lands on 0.5 through a divide; the filter has to tolerate
        // that rather than compare exactly.
        let fuzzy = CameraZoom(base: 2.0000001, minFactor: 1, maxFactor: 20)
        XCTAssertEqual(fuzzy.presets().first, 0.5)
    }

    func testASingleLensCameraOffersOneChipSoTheUIDrawsNone() {
        XCTAssertEqual(CameraZoom.unavailable.presets(), [1])
    }

    func testPresetsNeverComeBackEmpty() {
        // A lens whose whole range sits above 2x still needs something to
        // call home, or the UI has no selected chip at all.
        let telephotoOnly = CameraZoom(base: 1, minFactor: 3, maxFactor: 6)
        XCTAssertEqual(telephotoOnly.presets(), [3])
    }

    // MARK: Labels

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

    // MARK: Guards

    func testAZeroBaseCannotDivideEveryDisplayValueByNothing() {
        let broken = CameraZoom(base: 0, minFactor: 1, maxFactor: 4)
        XCTAssertEqual(broken.base, 1)
        XCTAssertEqual(broken.factor(forDisplay: 2), 2, accuracy: 0.0001)
    }
}
