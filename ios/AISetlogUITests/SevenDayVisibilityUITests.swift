import XCTest

final class SevenDayVisibilityUITests: XCTestCase {
    /// 1.5 (08f539d): the composer has no 拍几天 step any more — every new
    /// story is one day — so the 一日 / 7 日 rows must be gone, and picking a
    /// poster still names the story on the same page.
    func testPosterNamesTheStoryWithoutADaysStep() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
            "-demoEntries", "YES",
        ]
        app.launch()
        let compose = app.buttons["home-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15), "新建 button missing")
        compose.tap()
        XCTAssertTrue(app.buttons["by-time-entry"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["plan-one-day"].exists)
        XCTAssertFalse(app.buttons["plan-seven-day"].exists)
        ComposerUITest.writeShortList(in: app)
        let poster = app.buttons.matching(identifier: "poster-tile").firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 15))
        reveal(poster, in: app)
        poster.tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        // Picking a poster names the story after it.
        XCTAssertFalse((name.value as? String ?? "").isEmpty)
        XCTAssertTrue(app.buttons["company-solo"].exists)
        XCTAssertTrue(app.buttons["composer-start"].exists)
    }

    /// Short drags, not `swipeUp()`: a full swipe on a small phone throws the
    /// grid past the top of the page.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<6 where !element.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upward ? 0.6 : 0.3))
            let end = start.withOffset(CGVector(dx: 0, dy: upward ? -160 : 160))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    func testDemoIsReachableFromHomeWithoutSharedRoom() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
            // The demo entries this suite navigates through are opt-in as of
            // 1.3 — see `DemoEntries` in the app target. A UI test runs in its
            // own process, so the flag is spelled out rather than referenced.
            // Without it the home screen has no 房间演示 button and the camera
            // has no 示例片段, and on a runner with no camera there is then no
            // way to get footage anywhere.
            "-demoEntries", "YES",
        ]
        app.launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        XCTAssertTrue(demo.isHittable)
        demo.tap()
        XCTAssertTrue(app.staticTexts["local-room-notice"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.segmentedControls["local-room-members"].buttons.count, 2)
        XCTAssertTrue(app.buttons["room-make-vlog"].waitForExistence(timeout: UITestWait.media))
        XCTAssertTrue(app.buttons["room-chat"].exists)
        XCTAssertFalse(app.buttons["room-invite"].exists)
    }
}
