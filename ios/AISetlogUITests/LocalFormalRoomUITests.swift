import XCTest

/// Navigation and isolated-data UI evidence, not proof of moving video pixels.
///
/// The waits here are long because this test stitches real video on the way
/// through, and the machine matters: a shared-room stitch of three two-second
/// clips measures ~5s on a developer Mac and several times that on a CI runner,
/// which has no GPU to hand the work to. The timeouts that passed locally
/// (20–25s) failed on CI for that reason alone, so the media-dependent ones are
/// now 90s — long enough to be about correctness rather than about which
/// machine happened to run it.
final class LocalFormalRoomUITests: XCTestCase {
    func testFormalRoomChatFilmAndThreeMemberSwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese"]
        app.launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 90))
        XCTAssertTrue(app.staticTexts["local-room-notice"].exists)
        capture(app, "Formal two-member StoryTimelineView")
        app.buttons["聊天"].tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["本地演示 · 不会发送给朋友"].exists)
        let input = app.textFields["发消息…"]
        XCTAssertTrue(input.exists)
        input.tap()
        input.typeText("local UI message")
        app.buttons["发送"].tap()
        XCTAssertTrue(app.staticTexts["local UI message"].waitForExistence(timeout: 15))
        app.buttons["退出演示"].tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 15))
        app.buttons["看成片"].tap()
        XCTAssertTrue(app.buttons["调整"].waitForExistence(timeout: 90))
        XCTAssertFalse(app.buttons["保存"].isEnabled)
        XCTAssertFalse(app.buttons["分享"].isEnabled)
        capture(app, "Production FilmView with local real synthesis")
        // The shell's member selector remains outside the navigation stack;
        // changing it replaces only this local session and its navigation state.
        app.buttons["三人"].tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 90))
        app.buttons["聊天"].tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["local UI message"].exists)
        app.buttons["退出演示"].tap()
        capture(app, "Formal three-member StoryTimelineView")
        app.buttons["room-back"].tap()
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        XCTAssertTrue(demo.isHittable)
        demo.tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 90))
        XCTAssertTrue(app.buttons["两人"].isSelected)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
