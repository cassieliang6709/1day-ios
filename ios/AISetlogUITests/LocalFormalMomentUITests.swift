import XCTest

final class LocalFormalMomentUITests: XCTestCase {
    func testFullScreenMomentKeepsLocalChatAndRoomAlive() {
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
        XCTAssertTrue(app.buttons["home-room-demo"].waitForExistence(timeout: 15))
        app.buttons["home-room-demo"].tap()
        XCTAssertTrue(app.buttons["room-make-vlog"].waitForExistence(timeout: UITestWait.media))
        XCTAssertFalse(app.staticTexts["LOCAL-DEMO"].exists)
        let moment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "一起出发")).firstMatch
        XCTAssertTrue(moment.exists)
        // Mine is the first column, so its tile is the first match.
        moment.tap()
        let caption = app.buttons["moment-caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: UITestWait.media))
        // A tile opens that one take full screen — not the moment with
        // everyone stitched together. The video is the screen and 加字幕 / 重拍
        // / 再拍一段 / 聊天 float over its bottom edge; every one of them has
        // to be on screen and hittable.
        XCTAssertTrue(app.buttons["moment-caption"].isHittable)
        XCTAssertTrue(app.buttons["moment-rerecord"].isHittable)
        XCTAssertTrue(app.buttons["moment-add-take"].isHittable)
        XCTAssertFalse(app.buttons["moment-full-screen"].exists)

        // Two captions on one take: 加字幕 always adds another.
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
        // The composer says what the next message will be tagged with: the
        // moment's own name. It led with 「第 1 个瞬间」 until rooms stopped
        // numbering their moments on screen (1.5).
        XCTAssertTrue(app.staticTexts["chat-moment-about"].label.contains("一起出发"))
        app.buttons["chat-done"].tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        let close = app.buttons["moment-close"]
        XCTAssertTrue(close.exists, app.debugDescription)
        close.tap()
        XCTAssertTrue(app.buttons["room-make-vlog"].waitForExistence(timeout: 15))
        // Reopening must use this owner's still-readable scoped cache.
        moment.tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["moment-chat"].isHittable)
    }
}
