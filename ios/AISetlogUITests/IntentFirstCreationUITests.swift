import XCTest

final class IntentFirstCreationUITests: XCTestCase {
    func testIntentPrecedesEditableNameAndManualPathNeedsNoAI() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "english"]
        app.launch()
        // The composer is the left tab as of 1.3, not a plus in the corner.
        let plan = app.buttons["Plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 15), "Plan tab missing")
        plan.tap()
        // Above the racks, so it is the first thing on the screen after the
        // question itself — no rack to switch to first.
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
