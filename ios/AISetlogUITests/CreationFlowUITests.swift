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

        // The header button, not the home screen's "start today's story": that
        // one only exists when there's nothing in progress, so this test used
        // to depend on whatever the last run had left on the device.
        let newStory = app.buttons["新建故事"]
        XCTAssertTrue(newStory.waitForExistence(timeout: 6))
        newStory.tap()

        // The screen opens on prompts, so the grid and its library link are
        // the visible half.
        let byTime = app.buttons["按时间拍"]
        XCTAssertTrue(byTime.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["跟着题目拍"].exists)
        XCTAssertTrue(app.buttons["更多模板"].exists)

        // This tap is what the test used to be missing: it asserted the
        // time-only setup page while still on a prompted story, so it had been
        // failing for as long as the assertion had been there.
        byTime.tap()

        XCTAssertTrue(app.staticTexts["没有题目。拍到的每一段按时间排好，发生什么拍什么。"]
            .waitForExistence(timeout: 3))
        // Nothing greyed out beside it — the grid is gone, not disabled.
        XCTAssertFalse(app.buttons["更多模板"].exists)

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

        XCTAssertTrue(app.buttons["跟着题目拍"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["按时间拍"].exists)

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
