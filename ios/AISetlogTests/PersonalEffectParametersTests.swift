import XCTest
@testable import AISetlog

final class PersonalEffectParametersTests: XCTestCase {


    func testCentreIsTheUntouchedSource() {
        XCTAssertTrue(PersonalEffectParameters().isIdentity)
        XCTAssertEqual(PersonalEffectParameters(), .none)
        XCTAssertFalse(PersonalEffectParameters(exposure: 1).isIdentity)
        XCTAssertFalse(PersonalEffectParameters(temperature: -1).isIdentity)
        XCTAssertFalse(PersonalEffectParameters(contrast: 1).isIdentity)
    }

    func testValuesAreClampedToTheDialsBothWays() {
        let over = PersonalEffectParameters(exposure: 900, temperature: -900, contrast: 51)
        XCTAssertEqual(over.exposure, 50)
        XCTAssertEqual(over.temperature, -50)
        XCTAssertEqual(over.contrast, 50)
    }

    func testNonFiniteValuesFallBackToCentre() {
        let bad = PersonalEffectParameters(
            exposure: .nan, temperature: .infinity, contrast: -.infinity)
        XCTAssertTrue(bad.isIdentity)
    }


    func testExposureMapsToOnePointFiveStopsEitherWay() {
        XCTAssertEqual(PersonalEffectParameters(exposure: 50).exposureEV, 1.5, accuracy: 0.0001)
        XCTAssertEqual(PersonalEffectParameters(exposure: -50).exposureEV, -1.5, accuracy: 0.0001)
        XCTAssertEqual(PersonalEffectParameters().exposureEV, 0, accuracy: 0.0001)
    }

    func testWarmerMeansALowerTargetWhitePoint() {
        let neutral = PersonalEffectParameters.neutralTemperature
        XCTAssertEqual(PersonalEffectParameters().targetTemperature, neutral, accuracy: 0.0001)
        XCTAssertLessThan(PersonalEffectParameters(temperature: 50).targetTemperature, neutral)
        XCTAssertGreaterThan(PersonalEffectParameters(temperature: -50).targetTemperature, neutral)
        XCTAssertEqual(
            PersonalEffectParameters(temperature: 50).targetTemperature, 4500, accuracy: 0.0001)
    }

    func testContrastStaysInsideTheRangeThatKeepsAPictureReadable() {
        XCTAssertEqual(PersonalEffectParameters().contrastMultiplier, 1, accuracy: 0.0001)
        XCTAssertEqual(
            PersonalEffectParameters(contrast: 50).contrastMultiplier, 1.4, accuracy: 0.0001)
        XCTAssertEqual(
            PersonalEffectParameters(contrast: -50).contrastMultiplier, 0.6, accuracy: 0.0001)
    }


    func testRawValueSurvivesARoundTrip() {
        let original = PersonalEffectParameters(exposure: -12, temperature: 34, contrast: 7)
        let restored = PersonalEffectParameters(rawValue: original.rawValue)
        XCTAssertEqual(restored, original)
    }

    func testMalformedStoredValuesAreRejectedRatherThanGuessedAt() {
        XCTAssertNil(PersonalEffectParameters(rawValue: ""))
        XCTAssertNil(PersonalEffectParameters(rawValue: "1,2"))
        XCTAssertNil(PersonalEffectParameters(rawValue: "1,2,3,4"))
        XCTAssertNil(PersonalEffectParameters(rawValue: "1,two,3"))
    }

    func testTheOldStorageKeyIsNotReusedSoLegacyValuesCannotBeMisread() {
        XCTAssertNotEqual(PersonalEffectParameters.storageKey, "gentleLook.v1")
        XCTAssertNotEqual(PersonalEffectParameters.stickyKey, "gentleLook.sticky.v1")
    }

    func testCodableKeepsEachDialNamedRatherThanEncodingTheRawString() throws {
        let original = PersonalEffectParameters(exposure: 10, temperature: -20, contrast: 30)
        let data = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["exposure", "temperature", "contrast"])
        XCTAssertEqual(try JSONDecoder().decode(PersonalEffectParameters.self, from: data), original)
    }

    func testAMissingDialDecodesAsCentredNotAsBroken() throws {
        let data = try XCTUnwrap(#"{"exposure":25}"#.data(using: .utf8))
        let decoded = try JSONDecoder().decode(PersonalEffectParameters.self, from: data)
        XCTAssertEqual(decoded, PersonalEffectParameters(exposure: 25))
    }


    func testAGradeOnlySurvivesRelaunchWhenYouAskedItTo() {
        let graded = PersonalEffectParameters(exposure: 20)
        XCTAssertEqual(PersonalEffectParameters.onLaunch(stored: graded, sticky: true), graded)
        XCTAssertEqual(PersonalEffectParameters.onLaunch(stored: graded, sticky: false), .none)
        XCTAssertEqual(PersonalEffectParameters.onLaunch(stored: .none, sticky: true), .none)
    }
}
