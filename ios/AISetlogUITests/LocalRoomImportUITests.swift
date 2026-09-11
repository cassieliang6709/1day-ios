import XCTest

final class LocalRoomImportUITests: XCTestCase {
    func testMemberPickerCancelPreservesFormalRoomAndChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese"]
        app.launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 8))
        demo.tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 25))
        let importer = app.buttons["local-room-import"]
        XCTAssertTrue(importer.exists)
        importer.tap()
        let member = app.buttons["示例成员 2"]
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        member.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == '取消'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        cancel.tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 5))
        XCTAssertTrue(importer.isEnabled)
        XCTAssertFalse(app.staticTexts["导入失败，原视频未改动。请重新选择。"].exists)
        app.buttons["聊天"].tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 8))
        app.buttons["退出演示"].tap()
        XCTAssertTrue(app.buttons["看成片"].waitForExistence(timeout: 5))
    }
}
