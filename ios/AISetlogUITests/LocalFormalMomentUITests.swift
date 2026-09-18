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
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: UITestWait.media))
        XCTAssertFalse(app.staticTexts["LOCAL-DEMO"].exists)
        let moment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "一起出发")).firstMatch
        XCTAssertTrue(moment.exists)
        moment.tap()
        let caption = app.buttons["加字幕"]
        XCTAssertTrue(caption.waitForExistence(timeout: UITestWait.media))
        // One layout now: a big inset picture with 加字幕 / 重拍 / 聊天 side by
        // side under it. 全屏看 is gone, and so is the mode it led to. The
        // regression this test exists for is unchanged: every one of the three
        // has to be on screen and hittable.
        XCTAssertTrue(app.buttons["moment-caption"].isHittable)
        XCTAssertTrue(app.buttons["moment-rerecord"].isHittable)
        XCTAssertFalse(app.buttons["moment-full-screen"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Production one-layout StitchedMomentPreview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let chat = app.buttons["moment-chat"]
        XCTAssertTrue(chat.isHittable)
        chat.tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 15))
        // The composer says what the next message will be tagged with. It now
        // carries the moment's own prompt after the number, so match the part
        // that is the contract — the moment this chat was opened from.
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", "第 1 个瞬间"))
                .firstMatch.exists)
        app.buttons["退出演示"].tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "关闭", "xmark"])).firstMatch
        XCTAssertTrue(close.exists, app.debugDescription)
        close.tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 15))
        // Reopening must use this owner's still-readable scoped cache.
        moment.tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["moment-chat"].isHittable)
    }
}
