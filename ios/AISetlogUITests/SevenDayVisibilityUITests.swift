import XCTest

final class SevenDayVisibilityUITests: XCTestCase {
    func testSevenDaySwitchShowsTemplates() {
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
        // The composer is the left tab as of 1.3; the plus in the home header
        // is gone.
        let plan = app.buttons["计划"]
        XCTAssertTrue(plan.waitForExistence(timeout: 15), "计划 tab missing")
        plan.tap()
        let seven = app.buttons["七日"]
        XCTAssertTrue(seven.waitForExistence(timeout: 15))
        seven.tap()
        let moving = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "动起来的一周")).firstMatch
        XCTAssertTrue(moving.waitForExistence(timeout: 15))
        XCTAssertTrue(moving.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Seven day after switch"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["一日"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "完美的一天")).firstMatch.waitForExistence(timeout: 15))
        seven.tap()
        XCTAssertTrue(moving.waitForExistence(timeout: 15))
        // A poster opens the settings page as of 1.3 — it used to create the
        // story outright. The name is pre-filled from the template there, in a
        // field, which is also the first chance anybody gets to change it.
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "早起的人")).firstMatch.tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        XCTAssertEqual(name.value as? String, "7 天早起的人")
        // And the page asks who you are filming with before anything exists.
        XCTAssertTrue(app.buttons["company-solo"].exists)
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
        XCTAssertTrue(app.buttons["三人"].exists)
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: UITestWait.media))
        XCTAssertTrue(app.buttons["聊天"].exists)
        XCTAssertFalse(app.staticTexts["每个人的原片"].exists)
        XCTAssertFalse(app.buttons["邀请"].exists)
    }
}
