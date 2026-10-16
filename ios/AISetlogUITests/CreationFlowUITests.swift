import XCTest

/// Making a story, as of 1.5: the home header's 新建 opens one page with
/// every choice on it and a single 开始拍 at the bottom.
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

    /// The header's ＋ 新建, not the home screen's 「开始今天的故事」: that one
    /// only exists when there's nothing in progress, so a test that used it
    /// depended on whatever the last run had left on the device.
    private func openComposer() {
        let compose = app.buttons["home-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15), "新建 button missing")
        compose.tap()
    }

    func testTimeOnlyCreationExplainsThePromptFreeMode() throws {
        app.launch()
        openComposer()

        // 1.5: 不写，按时间拍 is one of three entry cards; choosing it shows
        // the prompt-free explanation on the same page, no sheet.
        let byTime = app.buttons["by-time-entry"]
        XCTAssertTrue(byTime.waitForExistence(timeout: 15))
        byTime.tap()

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

        // 1.5: one page. Three equal ways in, 自己写 first; 拍几天 as two
        // explained rows; no 更多模板 fold and no second 设置 sheet.
        XCTAssertTrue(app.buttons["write-own-entry"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["custom-prompts-entry"].exists)
        XCTAssertTrue(app.buttons["by-time-entry"].exists)
        XCTAssertLessThan(
            app.buttons["write-own-entry"].frame.minX,
            app.buttons["by-time-entry"].frame.minX)
        XCTAssertTrue(app.buttons["plan-one-day"].exists)
        XCTAssertTrue(app.buttons["plan-seven-day"].exists)
        XCTAssertFalse(app.buttons["more-templates"].exists)
        XCTAssertTrue(app.buttons.matching(identifier: "poster-tile").firstMatch.exists)
        // 谁来拍 and the camera are on the same page, with the one button.
        XCTAssertTrue(app.buttons["company-solo"].exists)
        XCTAssertTrue(app.buttons["camera-option-film"].exists)
        XCTAssertTrue(app.buttons["composer-start"].exists)
        XCTAssertFalse(app.buttons["下一步"].exists)
        // The plus in the home header is gone, not moved.
        XCTAssertFalse(app.buttons["新建故事"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "One-page composer"
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
