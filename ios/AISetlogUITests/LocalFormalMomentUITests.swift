import XCTest

final class LocalFormalMomentUITests: XCTestCase {
    func testFullScreenMomentKeepsLocalChatAndRoomAlive() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
            "-demoEntries", "YES",
        ]
        app.launch()
        app.openPersonalLibrary()
        XCTAssertTrue(app.buttons["home-room-demo"].waitForExistence(timeout: 15))
        app.buttons["home-room-demo"].tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: UITestWait.media))
        XCTAssertFalse(app.staticTexts["LOCAL-DEMO"].exists)
        let moment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "一起出发")).firstMatch
        XCTAssertTrue(moment.exists)
        moment.tap()
        let caption = app.buttons["moment-caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: UITestWait.media))
        XCTAssertTrue(app.buttons["moment-caption"].isHittable)
        XCTAssertTrue(app.buttons["moment-rerecord"].isHittable)
        XCTAssertTrue(app.buttons["moment-add-take"].isHittable)
        XCTAssertFalse(app.buttons["moment-full-screen"].exists)

        for words in ["早上好", "第一杯咖啡"] {
            caption.tap()
            XCTAssertTrue(app.buttons["caption-done"].waitForExistence(timeout: 10))
            app.typeText(words)
            app.buttons["caption-done"].tap()
            XCTAssertTrue(caption.waitForExistence(timeout: 10))
        }
        let stickers = app.staticTexts.matching(identifier: "caption-text")
        XCTAssertEqual(stickers.count, 2, app.debugDescription)
        XCTAssertTrue(app.staticTexts["早上好"].exists)
        XCTAssertTrue(app.staticTexts["第一杯咖啡"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Full-screen clip editor with two captions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let chat = app.buttons["moment-chat"]
        XCTAssertTrue(chat.isHittable)
        chat.tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["chat-moment-about"].label.contains("一起出发"))
        app.buttons["chat-done"].tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        let close = app.buttons["moment-close"]
        XCTAssertTrue(close.exists, app.debugDescription)
        close.tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: 15))
        moment.tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["moment-chat"].isHittable)
    }
}
