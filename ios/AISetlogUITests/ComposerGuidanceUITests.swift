import XCTest

final class ComposerGuidanceUITests: XCTestCase {
    func testComposerIsOnePageAndKeepsNameGuidance() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "english"]
        app.launch()
        app.openPersonalLibrary()
        let compose = app.buttons["home-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15), "New button missing")
        compose.tap()

        XCTAssertTrue(app.staticTexts["composer-question"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["composer-step"].exists)
        XCTAssertFalse(app.buttons["Next"].exists)
        XCTAssertFalse(app.buttons["templates-entry"].exists)

        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.tap()
        let original = name.value as? String ?? ""
        XCTAssertFalse(original.isEmpty)
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count))
        XCTAssertFalse(app.staticTexts["composer-name-needed"].exists)
        XCTAssertFalse(app.buttons["composer-start"].isEnabled)
        name.typeText("My edited story")
        XCTAssertEqual(name.value as? String, "My edited story")
    }
}
