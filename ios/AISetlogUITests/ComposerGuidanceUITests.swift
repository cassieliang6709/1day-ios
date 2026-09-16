import XCTest

final class ComposerGuidanceUITests: XCTestCase {
    func testStepsAndEmptyNameExplainDisabledCreationWithoutSaving() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "english"]
        app.launch()
        let create = app.buttons["New story"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let step = app.staticTexts["composer-step"]
        XCTAssertTrue(step.waitForExistence(timeout: 15))
        XCTAssertEqual(step.label, "1/2 Choose a style")
        app.buttons["Next"].tap()
        XCTAssertEqual(step.label, "2/2 Set up your story")
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
