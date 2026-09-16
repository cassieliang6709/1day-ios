import XCTest

final class SevenDayVisibilityUITests: XCTestCase {
    func testSevenDaySwitchShowsTemplates() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese"]
        app.launch()
        let create = app.buttons["新建故事"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
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
        XCTAssertTrue(app.buttons["下一步"].isHittable)
        app.buttons["一日"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "完美的一天")).firstMatch.waitForExistence(timeout: 15))
        seven.tap()
        XCTAssertTrue(moving.waitForExistence(timeout: 15))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "早起的人")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "早起的人、")).firstMatch.waitForExistence(timeout: 15))
    }

    func testDemoIsReachableFromHomeWithoutSharedRoom() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese"]
        app.launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        XCTAssertTrue(demo.isHittable)
        demo.tap()
        XCTAssertTrue(app.staticTexts["local-room-notice"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["三人"].exists)
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 90))
        XCTAssertTrue(app.buttons["聊天"].exists)
        XCTAssertFalse(app.staticTexts["每个人的原片"].exists)
        XCTAssertFalse(app.buttons["邀请"].exists)
    }
}
