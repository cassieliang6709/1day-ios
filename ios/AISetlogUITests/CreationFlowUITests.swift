import XCTest

final class CreationFlowUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
        ]
    }

    func testTimeOnlyCreationExplainsThePromptFreeMode() throws {
        app.launch()

        let start = app.buttons["开始今天的故事"]
        XCTAssertTrue(start.waitForExistence(timeout: 6))
        start.tap()

        XCTAssertTrue(app.staticTexts["按时间记录"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["主题挑战"].exists)
        XCTAssertTrue(app.staticTexts["Live With Me · 无题目"].exists)
        XCTAssertTrue(app.buttons["更多模板"].exists)

        let next = app.buttons["下一步"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()

        XCTAssertTrue(app.staticTexts["只记录时间"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["拍下当下，1Day 会自动保留拍摄时间；画面上的文字由每个人自己填写。"].exists)
        XCTAssertFalse(app.staticTexts["七个瞬间"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Live With Me setup"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHeaderNewStoryButtonOpensComposer() throws {
        app.launch()

        let newStory = app.buttons["新建故事"]
        XCTAssertTrue(newStory.waitForExistence(timeout: 6))
        newStory.tap()

        XCTAssertTrue(app.staticTexts["按时间记录"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["主题挑战"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "New story composer"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCustomPromptsStartWithTwoBlankRows() throws {
        app.launch()

        let newStory = app.buttons["新建故事"]
        XCTAssertTrue(newStory.waitForExistence(timeout: 6))
        newStory.tap()

        let custom = app.buttons["custom-prompts-entry"]
        XCTAssertTrue(custom.waitForExistence(timeout: 4))
        custom.tap()

        XCTAssertTrue(app.staticTexts["想拍什么，由你来写"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.textFields["custom-prompt-1"].exists)
        XCTAssertTrue(app.textFields["custom-prompt-2"].exists)
        XCTAssertFalse(app.textFields["custom-prompt-3"].exists)
    }
}
