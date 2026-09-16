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
        XCTAssertTrue(newStory.waitForExistence(timeout: 15))
        newStory.tap()

        // One row of four racks, replacing 跟着题目拍/按时间拍 stacked over
        // 一日/七日. All four are always there — 按时间 no longer takes the
        // other choices off screen, it just changes which posters are shown.
        let byTime = app.buttons["按时间"]
        XCTAssertTrue(byTime.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["一日"].exists)
        XCTAssertTrue(app.buttons["七日"].exists)
        XCTAssertTrue(app.buttons["自己写"].exists)

        byTime.tap()

        XCTAssertTrue(app.staticTexts["没有题目，只记录此刻发生的事。"]
            .waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["字幕由你自己在每段片子上填写，1Day 只负责保留拍摄时间。"].exists)

        // Its settings are behind the poster's gear now. Tapping the poster
        // itself would create the story, which this test deliberately doesn't.
        let gear = app.buttons.matching(identifier: "poster-settings").firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 15))
        gear.tap()

        XCTAssertTrue(app.staticTexts["只记录时间"].waitForExistence(timeout: 15))
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
        XCTAssertTrue(newStory.waitForExistence(timeout: 15))
        newStory.tap()

        XCTAssertTrue(app.buttons["一日"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["七日"].exists)
        XCTAssertTrue(app.buttons["按时间"].exists)
        XCTAssertTrue(app.buttons["自己写"].exists)
        // One screen: no counter and nothing to submit.
        XCTAssertFalse(app.buttons["下一步"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "New story composer"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCustomPromptsStartWithTwoBlankRows() throws {
        app.launch()

        let newStory = app.buttons["新建故事"]
        XCTAssertTrue(newStory.waitForExistence(timeout: 15))
        newStory.tap()

        // 自己写题目 used to sit at the bottom of every rack, under posters it
        // had nothing to do with. It is the 自己写 rack's own content now.
        let ownRack = app.buttons["自己写"]
        XCTAssertTrue(ownRack.waitForExistence(timeout: 15))
        ownRack.tap()

        let custom = app.buttons["custom-prompts-entry"]
        XCTAssertTrue(custom.waitForExistence(timeout: 15))
        custom.tap()

        XCTAssertTrue(app.staticTexts["想拍什么，由你来写"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.textFields["custom-prompt-1"].exists)
        XCTAssertTrue(app.textFields["custom-prompt-2"].exists)
        XCTAssertFalse(app.textFields["custom-prompt-3"].exists)
    }
}
