import XCTest

final class LocalFormalMomentUITests: XCTestCase {
    func testFullScreenMomentKeepsLocalChatAndRoomAlive() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese"]
        app.launch()
        XCTAssertTrue(app.buttons["home-room-demo"].waitForExistence(timeout: 15))
        app.buttons["home-room-demo"].tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 90))
        XCTAssertFalse(app.staticTexts["LOCAL-DEMO"].exists)
        let moment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "一起出发")).firstMatch
        XCTAssertTrue(moment.exists)
        moment.tap()
        let caption = app.buttons["加字幕"]
        XCTAssertTrue(caption.waitForExistence(timeout: 90))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Production full-screen StitchedMomentPreview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let chat = app.buttons.matching(identifier: "聊天").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(chat)
        chat?.tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["聊聊第 1 个瞬间"].exists)
        app.buttons["退出演示"].tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "关闭", "xmark"])).firstMatch
        XCTAssertTrue(close.exists, app.debugDescription)
        close.tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 15))
        // Reopening must use this owner's still-readable scoped cache.
        moment.tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(identifier: "聊天").allElementsBoundByIndex.contains { $0.isHittable })
    }
}
