import XCTest

final class IntentFirstCreationUITests: XCTestCase {
    func testIntentPrecedesEditableNameAndManualPathNeedsNoAI() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "english"]
        app.launch()
        app.openPersonalLibrary()
        let compose = app.buttons["home-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15), "New button missing")
        compose.tap()
        let own = app.buttons["composer-list-summary"]
        XCTAssertTrue(own.waitForExistence(timeout: 15))
        own.tap()
        let intent = app.textFields["today-intent"]
        let firstRow = app.textFields["custom-prompt-1"]
        XCTAssertTrue(intent.waitForExistence(timeout: 15))
        XCTAssertTrue(firstRow.exists)
        XCTAssertLessThan(intent.frame.minY, firstRow.frame.minY)
        XCTAssertFalse(app.buttons["suggest-prompts"].isEnabled)
        XCTAssertFalse(app.buttons["use-these-moments"].isEnabled)
        intent.tap()
        intent.typeText("Moving house")
        XCTAssertTrue(app.buttons["suggest-prompts"].isEnabled)
        firstRow.tap()
        firstRow.typeText("Empty room")
        XCTAssertFalse(app.buttons["use-these-moments"].isEnabled)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["composer-list-summary"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["composer-start"].isEnabled)
    }
}
