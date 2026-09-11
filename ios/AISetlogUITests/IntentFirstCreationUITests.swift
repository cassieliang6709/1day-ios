import XCTest

final class IntentFirstCreationUITests: XCTestCase {
    func testIntentPrecedesEditableNameAndManualPathNeedsNoAI() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "english"]
        app.launch()
        let create = app.buttons["New story"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let own = app.buttons["Write your own prompts"]
        XCTAssertTrue(own.waitForExistence(timeout: 15))
        own.tap()
        let intent = app.textFields["today-intent"]
        let name = app.textFields["custom-story-name"]
        XCTAssertTrue(intent.waitForExistence(timeout: 15))
        XCTAssertTrue(name.exists)
        XCTAssertLessThan(intent.frame.minY, name.frame.minY)
        XCTAssertFalse(app.buttons["suggest-prompts"].isEnabled)
        XCTAssertFalse(app.buttons["Use these"].isEnabled)
        // Do not call AI or save templates/stories. This verifies editable
        // production controls, not remote generation or final creation.
        name.tap()
        name.typeText("My own title")
        XCTAssertEqual(name.value as? String, "My own title")
        XCTAssertFalse(app.buttons["Use these"].isEnabled)
        app.buttons["Cancel"].tap()
    }
}
