import XCTest

final class ComposerGuidanceUITests: XCTestCase {
    /// The composer is one page, and "a name is needed" shows up where a name
    /// can actually be typed.
    ///
    /// This test has survived four shapes of the screen: a 1/2 → 2/2 wizard, a
    /// poster rack that submitted on tap, posters opening a settings page, and
    /// now (1.5) no templates at all — 按时间拍 names the story for the date.
    func testComposerIsOnePageAndKeepsNameGuidance() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "english"]
        app.launch()
        // 1.5: the composer is the header's + New, not a tab.
        let compose = app.buttons["home-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15), "New button missing")
        compose.tap()

        XCTAssertTrue(app.staticTexts["composer-question"].waitForExistence(timeout: 15))
        // No progress counter and no Next: choosing and submitting are one page.
        XCTAssertFalse(app.staticTexts["composer-step"].exists)
        XCTAssertFalse(app.buttons["Next"].exists)
        // No templates (1.5).
        XCTAssertFalse(app.buttons["templates-entry"].exists)
        XCTAssertTrue(app.buttons["by-time-entry"].isSelected)

        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.tap()
        let original = name.value as? String ?? ""
        XCTAssertFalse(original.isEmpty)
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count))
        let guidance = app.staticTexts["composer-name-needed"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 15))
        XCTAssertEqual(guidance.label, "Give the topic a name first")
        name.typeText("My edited story")
        XCTAssertFalse(guidance.exists)
        XCTAssertEqual(name.value as? String, "My edited story")
        // Deliberately never create or join a room, or call the AI service.
    }
}
