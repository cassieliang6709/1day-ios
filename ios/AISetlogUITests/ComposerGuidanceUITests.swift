import XCTest

final class ComposerGuidanceUITests: XCTestCase {
    /// The rack has nothing to submit, and the name guidance lives on the page
    /// a poster opens.
    ///
    /// Three shapes of this screen, and this test has survived all three:
    /// `1/2 Choose a style` → Next → `2/2 Set up your story` with both labels
    /// asserted; then "the poster is the submit button" with the settings
    /// behind a gear; now the poster opens the settings page and the page's own
    /// button is what creates the story. What stays worth pinning is that the
    /// rack itself has no second step, and that "a name is needed" still shows
    /// up where a name can actually be typed.
    func testPosterOpensTheSettingsPageAndKeepsNameGuidance() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "english"]
        app.launch()
        let plan = app.buttons["Plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 15), "Plan tab missing")
        plan.tap()

        XCTAssertTrue(app.staticTexts["composer-question"].waitForExistence(timeout: 15))
        // No progress counter and no bottom button: both only made sense when
        // choosing and submitting were two separate taps.
        XCTAssertFalse(app.staticTexts["composer-step"].exists)
        XCTAssertFalse(app.buttons["Next"].exists)

        // No gear to find: the poster is the way in, and tapping it no longer
        // creates anything by itself.
        XCTAssertFalse(app.buttons.matching(identifier: "poster-settings").firstMatch.exists)
        let poster = app.buttons.matching(identifier: "poster-tile").firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 15))
        poster.tap()

        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.tap()
        let original = name.value as? String ?? ""
        XCTAssertFalse(original.isEmpty)
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count))
        let guidance = app.staticTexts["composer-name-needed"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 15))
        XCTAssertEqual(guidance.label, "A name is needed before saving.")
        name.typeText("My edited story")
        XCTAssertFalse(guidance.exists)
        XCTAssertEqual(name.value as? String, "My edited story")
        // Deliberately never create or join a room, or call the AI service.
    }
}
