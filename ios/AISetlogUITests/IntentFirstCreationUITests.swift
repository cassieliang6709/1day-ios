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
        // 写今天的清单 is one editor: the sentence about today with a small
        // Draft it, then the list.
        let own = app.buttons["write-own-entry"]
        XCTAssertTrue(own.waitForExistence(timeout: 15))
        own.tap()
        let intent = app.textFields["today-intent"]
        let firstRow = app.textFields["custom-prompt-1"]
        XCTAssertTrue(intent.waitForExistence(timeout: 15))
        XCTAssertTrue(firstRow.exists)
        XCTAssertLessThan(intent.frame.minY, firstRow.frame.minY)
        XCTAssertFalse(app.buttons["suggest-prompts"].isEnabled)
        XCTAssertFalse(app.buttons["use-these-moments"].isEnabled)
        // Typing the sentence enables the helper; never tap it (no AI call).
        intent.tap()
        intent.typeText("Moving house")
        XCTAssertTrue(app.buttons["suggest-prompts"].isEnabled)
        // One row is not a list yet.
        firstRow.tap()
        firstRow.typeText("Empty room")
        XCTAssertFalse(app.buttons["use-these-moments"].isEnabled)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["composer-list-summary"].exists)
    }
}
