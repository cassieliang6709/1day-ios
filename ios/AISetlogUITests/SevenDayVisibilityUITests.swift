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
        // The composer is the header's ＋ 新建 as of 1.5.
        let compose = app.buttons["home-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15), "新建 button missing")
        compose.tap()
        // One page as of 1.5: two rows say how many days, and the chosen
        // row opens its own posters underneath. No 更多模板, no 一日/七日 pills.
        let oneDayRow = app.buttons["plan-one-day"]
        let sevenDayRow = app.buttons["plan-seven-day"]
        XCTAssertTrue(sevenDayRow.waitForExistence(timeout: 15), "7-day row missing")
        sevenDayRow.tap()
        XCTAssertTrue(sevenDayRow.isSelected)
        let moving = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "动起来的一周")).firstMatch
        XCTAssertTrue(moving.waitForExistence(timeout: 15))
        XCTAssertTrue(moving.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Seven day after switch"
        shot.lifetime = .keepAlways
        add(shot)
        oneDayRow.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "完美的一天")).firstMatch.waitForExistence(timeout: 15))
        sevenDayRow.tap()
        XCTAssertTrue(moving.waitForExistence(timeout: 15))
        // Picking a seven-day poster names the story after it, in the field
        // on the same page — the first chance anybody gets to change it.
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "早起的人")).firstMatch.tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        XCTAssertEqual(name.value as? String, "7 天早起的人")
        // And the page asks who you are filming with before anything exists.
        XCTAssertTrue(app.buttons["company-solo"].exists)
        XCTAssertTrue(app.buttons["composer-start"].exists)
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
        XCTAssertTrue(app.buttons["生成 vlog"].waitForExistence(timeout: UITestWait.media))
        XCTAssertTrue(app.buttons["聊天"].exists)
        XCTAssertFalse(app.staticTexts["每个人的原片"].exists)
        XCTAssertFalse(app.buttons["邀请"].exists)
    }
}
