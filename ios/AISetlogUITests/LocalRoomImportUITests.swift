import XCTest

final class LocalRoomImportUITests: XCTestCase {
    func testMemberPickerCancelPreservesFormalRoomAndChat() {
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
        demo.tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: UITestWait.media))
        let importer = app.buttons["local-room-import"]
        XCTAssertTrue(importer.exists)
        importer.tap()
        let member = app.buttons["示例成员 2"]
        XCTAssertTrue(member.waitForExistence(timeout: 15))
        member.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == '取消'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        cancel.tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 15))
        XCTAssertTrue(importer.isEnabled)
        XCTAssertFalse(app.staticTexts["导入失败，原视频未改动。请重新选择。"].exists)
        app.buttons["聊天"].tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 15))
        app.buttons["退出演示"].tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 15))
    }
}
