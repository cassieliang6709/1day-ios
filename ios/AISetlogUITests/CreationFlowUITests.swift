import XCTest

/// Making a story, as of 1.3: the 计划 tab, a rack of posters, and one page of
/// settings behind whichever poster you tap.
///
/// Two things these tests used to walk are gone and are not coming back, so
/// they are asserted absent rather than quietly dropped:
///
/// - **The 新建故事 button.** A 36pt wordless plus in the corner of the home
///   screen. It is the left tab now, labelled 计划.
/// - **The poster gear.** Settings were optional behind a 26pt icon; a poster
///   tap created the story outright and answered 谁一起拍 as 自己来 without
///   asking. The poster opens the page now, so the poster *is* the gear.
final class CreationFlowUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
        ]
    }

    /// The 计划 tab, not the home screen's 「开始今天的故事」: that one only
    /// exists when there's nothing in progress, so a test that used it depended
    /// on whatever the last run had left on the device.
    private func openComposer() {
        let plan = app.buttons["计划"]
        XCTAssertTrue(plan.waitForExistence(timeout: 15), "计划 tab missing")
        plan.tap()
    }

    func testTimeOnlyCreationExplainsThePromptFreeMode() throws {
        app.launch()
        openComposer()

        // One row of four racks, replacing 跟着题目拍/按时间拍 stacked over
        // 一日/七日. All four are always there — 按时间 no longer takes the
        // other choices off screen, it just changes which posters are shown.
        let byTime = app.buttons["按时间"]
        XCTAssertTrue(byTime.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["一日"].exists)
        XCTAssertTrue(app.buttons["七日"].exists)
        XCTAssertTrue(app.buttons["自己写"].exists)

        byTime.tap()

        // A poster tap opens the settings page. It used to create the story, so
        // this test deliberately avoided it and went through the gear instead;
        // with the gear gone the poster is the only way in, and it no longer
        // creates anything by itself.
        let poster = app.buttons.matching(identifier: "poster-tile").firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 15), "no poster on the 按时间 rack")
        poster.tap()

        XCTAssertTrue(app.staticTexts["只记录时间"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["拍下当下，1Day 会自动保留拍摄时间；画面上的文字由每个人自己填写。"].exists)
        XCTAssertFalse(app.staticTexts["七个瞬间"].exists)
        // The page asks 谁一起拍 before anything exists — the whole reason the
        // gear went away.
        XCTAssertTrue(app.buttons["company-solo"].exists)
        XCTAssertTrue(app.buttons["company-with-friends"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Time-only setup page"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPlanTabOpensTheComposer() throws {
        app.launch()
        openComposer()

        XCTAssertTrue(app.buttons["一日"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["七日"].exists)
        XCTAssertTrue(app.buttons["按时间"].exists)
        XCTAssertTrue(app.buttons["自己写"].exists)
        // No counter and nothing to submit on this screen: the page behind a
        // poster is where a story gets made.
        XCTAssertFalse(app.buttons["下一步"].exists)
        // The plus in the home header is gone, not moved.
        XCTAssertFalse(app.buttons["新建故事"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Plan tab composer"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCustomPromptsStartWithTwoBlankRows() throws {
        app.launch()
        openComposer()

        // 自己写题目 sits above the racks, not at the bottom under posters it
        // has nothing to do with — so it is reachable without changing rack.
        let custom = app.buttons["custom-prompts-entry"]
        XCTAssertTrue(custom.waitForExistence(timeout: 15))
        custom.tap()

        XCTAssertTrue(app.staticTexts["想拍什么，由你来写"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.textFields["custom-prompt-1"].exists)
        XCTAssertTrue(app.textFields["custom-prompt-2"].exists)
        XCTAssertFalse(app.textFields["custom-prompt-3"].exists)
    }
}
