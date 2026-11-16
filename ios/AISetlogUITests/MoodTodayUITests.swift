import XCTest

final class MoodTodayUITests: XCTestCase {
    func testPickedMoodCollapsesAndCanBeChanged() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese"]
        app.launch()

        let selected = app.buttons["mood-today-selected"]
        XCTAssertTrue(app.descendants(matching: .any)["mood-today-card"].waitForExistence(timeout: 15))
        if selected.exists { selected.tap() }
        XCTAssertTrue(app.buttons["mood-happy"].waitForExistence(timeout: 5))
        app.buttons["mood-happy"].tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertEqual(selected.label, "开心")
        XCTAssertFalse(app.buttons["mood-calm"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Selected mood"
        attachment.lifetime = .keepAlways
        add(attachment)

        selected.tap()
        for mood in ["happy", "calm", "tired", "sad", "angry"] {
            XCTAssertTrue(app.buttons["mood-\(mood)"].waitForExistence(timeout: 5))
        }
        app.buttons["mood-calm"].tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertEqual(selected.label, "平静")
        XCTAssertFalse(app.buttons["mood-happy"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(selected.waitForExistence(timeout: 15))
        XCTAssertEqual(selected.label, "平静")
        XCTAssertFalse(app.buttons["mood-happy"].exists)
    }
}
