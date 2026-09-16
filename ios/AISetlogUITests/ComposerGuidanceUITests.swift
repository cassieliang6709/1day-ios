import XCTest

final class ComposerGuidanceUITests: XCTestCase {
    /// The composer is one screen: the rack of posters, and nothing to submit.
    ///
    /// This used to walk `1/2 Choose a style` → Next → `2/2 Set up your story`
    /// and assert both labels. Both screens and the button between them are
    /// gone — a poster tap creates the story — so what is worth pinning is
    /// that the screen has no second step to reach and that the name guidance
    /// still appears where a name can still be typed: the settings sheet.
    func testOneScreenComposerKeepsNameGuidanceBehindThePosterGear() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "english"]
        app.launch()
        let create = app.buttons["New story"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()

        XCTAssertTrue(app.staticTexts["composer-question"].waitForExistence(timeout: 15))
        // No progress counter and no bottom button: both only made sense when
        // choosing and submitting were two separate taps.
        XCTAssertFalse(app.staticTexts["composer-step"].exists)
        XCTAssertFalse(app.buttons["Next"].exists)

        let gear = app.buttons.matching(identifier: "poster-settings").firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 15))
        gear.tap()

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
