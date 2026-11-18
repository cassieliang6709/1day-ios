import XCTest

final class SevenDayVisibilityUITests: XCTestCase {
    func testByTimeNamesTheStoryWithoutADaysStep() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
            "-demoEntries", "YES",
        ]
        app.launch()
        app.openPersonalLibrary()
        let compose = app.buttons["home-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15), "新建 button missing")
        compose.tap()
        XCTAssertTrue(app.buttons["composer-list-summary"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["by-time-entry"].exists)
        XCTAssertFalse(app.buttons["plan-one-day"].exists)
        XCTAssertFalse(app.buttons["plan-seven-day"].exists)
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        XCTAssertFalse((name.value as? String ?? "").isEmpty)
        XCTAssertFalse(app.buttons["company-solo"].exists)
        XCTAssertTrue(app.buttons["composer-start"].exists)
    }

    func testDemoIsReachableFromHomeWithoutSharedRoom() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
            "-demoEntries", "YES",
        ]
        app.launch()
        app.openPersonalLibrary()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        XCTAssertTrue(demo.isHittable)
        demo.tap()
        XCTAssertTrue(app.staticTexts["local-room-notice"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.segmentedControls["local-room-members"].buttons.count, 2)
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: UITestWait.media))
        XCTAssertFalse(app.buttons["room-invite"].exists)
    }
}
