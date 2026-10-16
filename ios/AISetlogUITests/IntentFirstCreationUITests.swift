import XCTest

final class IntentFirstCreationUITests: XCTestCase {
    func testIntentPrecedesEditableNameAndManualPathNeedsNoAI() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "english"]
        app.launch()
        // 1.5: the composer opens from the home header's + New, not a tab.
        let compose = app.buttons["home-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15), "New button missing")
        compose.tap()
        // 自己写 is the first of the composer's three entry cards, and it
        // opens the write-your-own editor.
        let own = app.buttons["write-own-entry"]
        XCTAssertTrue(own.waitForExistence(timeout: 15))
        own.tap()
        let intent = app.textFields["today-intent"]
        let name = app.textFields["custom-story-name"]
        XCTAssertTrue(intent.waitForExistence(timeout: 15))
        XCTAssertTrue(name.exists)
        XCTAssertLessThan(intent.frame.minY, name.frame.minY)
        XCTAssertFalse(app.buttons["suggest-prompts"].isEnabled)
        XCTAssertFalse(app.buttons["use-these-moments"].isEnabled)
        // Do not call AI or save templates/stories. This verifies editable
        // production controls, not remote generation or final creation.
        name.tap()
        name.typeText("My own title")
        XCTAssertEqual(name.value as? String, "My own title")
        XCTAssertFalse(app.buttons["use-these-moments"].isEnabled)
        app.buttons["Cancel"].tap()
    }
}
