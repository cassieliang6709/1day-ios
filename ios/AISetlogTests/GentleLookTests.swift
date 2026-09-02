import XCTest
@testable import AISetlog

/// The look is three numbers between 0 and 1, and everything that matters about
/// it is arithmetic: what "off" means, what a slider at either end produces,
/// and whether a value survives a round trip through storage. None of that
/// needs a video, so all of it is tested here rather than by squinting at a
/// simulator.
final class GentleLookTests: XCTestCase {

    // MARK: Off means off

    func testDefaultIsOff() {
        XCTAssertEqual(GentleLook(), .none)
        XCTAssertTrue(GentleLook.none.isIdentity)
    }

    func testAnyDialOffZeroIsNotOff() {
        XCTAssertFalse(GentleLook(smoothing: 0.01).isIdentity)
        XCTAssertFalse(GentleLook(brightness: 0.01).isIdentity)
        XCTAssertFalse(GentleLook(warmth: 0.01).isIdentity)
    }

    func testEveryPresetButNoneChangesSomething() {
        for (key, look) in GentleLook.presets where key != "look_none" {
            XCTAssertFalse(look.isIdentity, "\(key) would be a no-op")
        }
    }

    /// Off has to leave the picture alone in the arithmetic too, not just in the
    /// `isIdentity` shortcut — otherwise the day someone forgets to check the
    /// flag, "原样" quietly desaturates.
    func testOffDerivesToANeutralChain() {
        let p = GentleLook.none.parameters
        XCTAssertEqual(p.blurRadius, 0)
        XCTAssertEqual(p.blurOpacity, 0)
        XCTAssertEqual(p.softLightOpacity, 0)
        XCTAssertEqual(p.brightnessDelta, 0)
        XCTAssertEqual(p.saturation, 1)
        XCTAssertEqual(p.temperature, GentleLook.neutralTemperature)
        XCTAssertEqual(p.tint, 0)
    }

    // MARK: Clamping

    func testValuesOutsideZeroToOneAreClamped() {
        let over = GentleLook(smoothing: 4, brightness: 1.0001, warmth: 99)
        XCTAssertEqual(over, GentleLook(smoothing: 1, brightness: 1, warmth: 1))

        let under = GentleLook(smoothing: -1, brightness: -0.5, warmth: -0)
        XCTAssertEqual(under, .none)
    }

    /// A slider can't produce these. `@AppStorage` and an old JSON file can.
    func testNonFiniteValuesFallBackToOff() {
        let bad = GentleLook(
            smoothing: .nan, brightness: .infinity, warmth: -.infinity)
        XCTAssertEqual(bad, .none)
    }

    // MARK: Derived parameters

    func testFullSmoothingHitsTheCeilingAndNothingElse() {
        let p = GentleLook(smoothing: 1).parameters
        XCTAssertEqual(p.blurRadius, 8.0)
        XCTAssertEqual(p.blurOpacity, 0.35)
        XCTAssertEqual(p.softLightOpacity, 0.55)
        // The glow carries more of the effect than the blur does, at every
        // setting. Swap these and "柔光" starts looking like a smudge.
        XCTAssertGreaterThan(p.softLightOpacity, p.blurOpacity)
        XCTAssertEqual(p.brightnessDelta, 0)
        XCTAssertEqual(p.saturation, 1)
        XCTAssertEqual(p.temperature, GentleLook.neutralTemperature)
    }

    /// Saturation comes *down* as brightness goes up. Lifting a face without
    /// that makes the skin go orange, so the two move together by design and
    /// this is the test that says so.
    func testFullBrightnessLiftsAndDesaturates() {
        let p = GentleLook(brightness: 1).parameters
        XCTAssertEqual(p.brightnessDelta, 0.06, accuracy: 1e-9)
        XCTAssertEqual(p.saturation, 0.92, accuracy: 1e-9)
        XCTAssertEqual(p.blurRadius, 0)
    }

    func testFullWarmthMovesTheWhitePointTowardsAfternoon() {
        let p = GentleLook(warmth: 1).parameters
        XCTAssertEqual(p.temperature, 5200.0)
        XCTAssertEqual(p.tint, 8.0)
        // Warmer means a *lower* kelvin target. Getting this backwards makes
        // the "warm" preset blue, which is the kind of bug that looks like a
        // broken filter rather than a swapped constant.
        XCTAssertLessThan(p.temperature, GentleLook.neutralTemperature)
    }

    func testEveryDialIsMonotonic() {
        let steps = stride(from: 0.0, through: 1.0, by: 0.1).map { $0 }
        for (a, b) in zip(steps, steps.dropFirst()) {
            XCTAssertLessThan(
                GentleLook(smoothing: a).parameters.blurRadius,
                GentleLook(smoothing: b).parameters.blurRadius)
            XCTAssertLessThan(
                GentleLook(smoothing: a).parameters.blurOpacity,
                GentleLook(smoothing: b).parameters.blurOpacity)
            XCTAssertLessThan(
                GentleLook(brightness: a).parameters.brightnessDelta,
                GentleLook(brightness: b).parameters.brightnessDelta)
            XCTAssertGreaterThan(
                GentleLook(brightness: a).parameters.saturation,
                GentleLook(brightness: b).parameters.saturation)
            XCTAssertGreaterThan(
                GentleLook(warmth: a).parameters.temperature,
                GentleLook(warmth: b).parameters.temperature)
        }
    }

    /// The ceilings are the whole promise of this feature: it stops short of
    /// looking retouched. Nothing derived may leave the range a `CIFilter`
    /// expects, at any setting.
    func testNoSettingProducesAnUnreasonableChain() {
        for s in stride(from: 0.0, through: 1.0, by: 0.25) {
            for b in stride(from: 0.0, through: 1.0, by: 0.25) {
                for w in stride(from: 0.0, through: 1.0, by: 0.25) {
                    let p = GentleLook(smoothing: s, brightness: b, warmth: w).parameters
                    XCTAssertTrue((0...8).contains(p.blurRadius))
                    XCTAssertTrue((0...0.35).contains(p.blurOpacity))
                    XCTAssertTrue((0...0.55).contains(p.softLightOpacity))
                    XCTAssertTrue((0...0.06).contains(p.brightnessDelta))
                    XCTAssertTrue((0.9...1).contains(p.saturation))
                    XCTAssertTrue((5000...6500).contains(p.temperature))
                    XCTAssertTrue((0...8).contains(p.tint))
                }
            }
        }
    }

    // MARK: Presets

    func testPresetsAreInPickerOrderStartingFromOff() {
        XCTAssertEqual(
            GentleLook.presets.map(\.key),
            ["look_none", "look_clean", "look_soft", "look_warm"])
        XCTAssertEqual(GentleLook.presets.first?.look, GentleLook.none)
    }

    func testPresetsAreDistinct() {
        let looks = GentleLook.presets.map(\.look)
        for (i, look) in looks.enumerated() {
            for other in looks[(i + 1)...] {
                XCTAssertNotEqual(look, other)
            }
        }
    }

    func testAPresetKnowsWhichPresetItIs() {
        XCTAssertEqual(GentleLook.none.presetKey, "look_none")
        XCTAssertEqual(GentleLook.clean.presetKey, "look_clean")
        XCTAssertEqual(GentleLook.soft.presetKey, "look_soft")
        XCTAssertEqual(GentleLook.warm.presetKey, "look_warm")
    }

    /// Move a slider and the picker highlights nothing. That's the honest
    /// answer — you're no longer on 柔光, you're on something near it.
    func testACustomValueIsNotAPreset() {
        var nudged = GentleLook.soft
        nudged = GentleLook(
            smoothing: nudged.smoothing + 0.05,
            brightness: nudged.brightness,
            warmth: nudged.warmth)
        XCTAssertNil(nudged.presetKey)
    }

    /// 干净 should read as less than 柔光 on the dial it's named for, or the
    /// picker order is a lie.
    func testCleanIsGentlerThanSoft() {
        XCTAssertLessThan(GentleLook.clean.smoothing, GentleLook.soft.smoothing)
        XCTAssertLessThan(GentleLook.clean.brightness, GentleLook.soft.brightness)
    }

    func testWarmIsTheWarmestPreset() {
        for (key, look) in GentleLook.presets where key != "look_warm" {
            XCTAssertLessThan(look.warmth, GentleLook.warm.warmth, "\(key)")
        }
    }

    // MARK: Storage

    func testRawValueRoundTrips() {
        for (key, look) in GentleLook.presets {
            XCTAssertEqual(GentleLook(rawValue: look.rawValue), look, "\(key)")
        }
        let custom = GentleLook(smoothing: 0.1234, brightness: 0.5, warmth: 0.9876)
        XCTAssertEqual(GentleLook(rawValue: custom.rawValue), custom)
    }

    func testMalformedRawValueIsRejected() {
        for bad in ["", "0.5", "0.5,0.5", "0.5,0.5,0.5,0.5", "a,b,c", "0.5,,0.5"] {
            XCTAssertNil(GentleLook(rawValue: bad), "accepted \(bad.debugDescription)")
        }
    }

    /// A stored string from a future build with wider ceilings shouldn't crash
    /// or produce a plastic face — it should clamp.
    func testOutOfRangeRawValueClamps() {
        XCTAssertEqual(GentleLook(rawValue: "9,-9,0.5"),
                       GentleLook(smoothing: 1, brightness: 0, warmth: 0.5))
    }

    /// "Keep this from now on" off means the app opens on 原样 — a dial you
    /// moved once, on a day you didn't like your face, shouldn't become how you
    /// see every day after it.
    func testTheLookIsForgottenOnLaunchUnlessYouAskedItToStay() {
        XCTAssertEqual(GentleLook.onLaunch(stored: .soft, sticky: false), .none)
        XCTAssertEqual(GentleLook.onLaunch(stored: .soft, sticky: true), .soft)
        XCTAssertEqual(GentleLook.onLaunch(stored: .none, sticky: false), .none)

        let custom = GentleLook(smoothing: 0.2, brightness: 0.7, warmth: 0.1)
        XCTAssertEqual(GentleLook.onLaunch(stored: custom, sticky: true), custom)
        XCTAssertEqual(GentleLook.onLaunch(stored: custom, sticky: false), .none)
    }

    /// The `Picker` in Settings selects by tag, which needs this.
    func testEqualLooksHashAlike() {
        XCTAssertEqual(GentleLook.soft.hashValue, GentleLook(
            smoothing: 0.60, brightness: 0.50, warmth: 0.35).hashValue)
        XCTAssertEqual(Set(GentleLook.presets.map(\.look)).count, 4)
    }

    func testCodableRoundTrips() throws {
        let data = try JSONEncoder().encode(GentleLook.warm)
        XCTAssertEqual(try JSONDecoder().decode(GentleLook.self, from: data), .warm)
    }

    /// Films saved before this feature existed have none of these keys. They
    /// should decode as "原样", not fail to decode at all.
    func testDecodingWithMissingKeysGivesOff() throws {
        let old = Data("{}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(GentleLook.self, from: old), .none)

        let partial = Data(#"{"warmth":0.8}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(GentleLook.self, from: partial),
            GentleLook(warmth: 0.8))
    }
}
