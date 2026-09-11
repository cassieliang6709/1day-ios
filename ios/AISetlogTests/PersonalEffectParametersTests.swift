import XCTest
@testable import AISetlog

final class PersonalEffectParametersTests: XCTestCase {
    func testDefaultsAreIdentity() {
        let parameters = PersonalEffectParameters()
        XCTAssertTrue(parameters.isIdentity)
        XCTAssertEqual(parameters.exposureEV, 0)
        XCTAssertEqual(parameters.contrastMultiplier, 1)
    }

    func testValuesClampToProductRange() {
        let parameters = PersonalEffectParameters(exposure: 100, temperature: -100, contrast: .infinity)
        XCTAssertEqual(parameters.exposure, 50)
        XCTAssertEqual(parameters.temperature, -50)
        XCTAssertEqual(parameters.contrast, 0)
    }

    func testMappingUsesCoreImageSafeRanges() {
        let parameters = PersonalEffectParameters(exposure: -50, temperature: 50, contrast: 50)
        XCTAssertEqual(parameters.exposureEV, -1.5)
        XCTAssertEqual(parameters.targetTemperature, 8500)
        XCTAssertEqual(parameters.contrastMultiplier, 1.4)
    }

    func testRoundTrip() throws {
        let original = PersonalEffectParameters(exposure: -12, temperature: 23, contrast: 41)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(PersonalEffectParameters.self, from: data), original)
    }
}
