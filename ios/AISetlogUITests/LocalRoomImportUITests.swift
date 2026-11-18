import XCTest

final class LocalRoomImportUITests: XCTestCase {
    func testMemberPickerCancelPreservesFormalRoomAndChat() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
            "-demoEntries", "YES",
        ]
        app.launch()
        app.openPersonalLibrary()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: UITestWait.media))
        let importer = app.buttons["local-room-import"]
        XCTAssertTrue(importer.exists)
        importer.tap()
        let member = app.buttons["示例成员 2"]
        XCTAssertTrue(member.waitForExistence(timeout: 15))
        member.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == '取消'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        cancel.tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: 15))
        XCTAssertTrue(importer.isEnabled)
        XCTAssertFalse(app.staticTexts["local-room-import-error"].exists)
        app.buttons["room-chat"].tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 15))
        app.buttons["chat-done"].tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: 15))
    }
}
