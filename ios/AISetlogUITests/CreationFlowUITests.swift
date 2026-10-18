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

    func testTimeOnlyCreationAsksNothingMore() throws {
        app.launch()
        openComposer()

        // 1.5: 不写，按时间拍 is the second of two ways in. Choosing it adds
        // nothing under the name — no list row, no sheet.
        let byTime = app.buttons["by-time-entry"]
        XCTAssertTrue(byTime.waitForExistence(timeout: 15))
        byTime.tap()
        XCTAssertTrue(byTime.isSelected)
        XCTAssertFalse(app.buttons["composer-list-summary"].exists)
        // 自己拍 / 和朋友一起拍 is a two-part control, asked before anything exists.
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

        // 1.5: one page. Two ways in (写今天的清单 above 按时间拍), 拍几天 as
        // two rows, templates in a grid with 更多模板, no second 设置 sheet.
        let list = app.buttons["write-own-entry"]
        let byTime = app.buttons["by-time-entry"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        XCTAssertTrue(byTime.exists)
        XCTAssertLessThan(list.frame.minY, byTime.frame.minY)
        XCTAssertFalse(app.buttons["custom-prompts-entry"].exists)
        // No 拍几天 step since 08f539d: every new story is one day.
        XCTAssertFalse(app.buttons["plan-one-day"].exists)
        XCTAssertFalse(app.buttons["plan-seven-day"].exists)
        XCTAssertFalse(app.buttons["made-before"].exists)
        // Templates belong to 写今天的清单; the default 按时间拍 shows none.
        XCTAssertFalse(app.buttons.matching(identifier: "poster-tile").firstMatch.exists)
        // Who's filming and the camera are on the same page, with the one button.
        XCTAssertTrue(app.buttons["company-solo"].exists)
        XCTAssertTrue(app.buttons["camera-option-film"].exists)
        XCTAssertTrue(app.buttons["composer-start"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "One-page composer"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWriteListOpensOneEditorWithTwoBlankRows() throws {
        app.launch()
        openComposer()

        let list = app.buttons["write-own-entry"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        list.tap()

        // One editor for both ways of writing: the sentence and 帮我写 on
        // top, then the list.
        XCTAssertTrue(app.textFields["today-intent"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["suggest-prompts"].exists)
        XCTAssertTrue(app.textFields["custom-prompt-1"].exists)
        XCTAssertTrue(app.textFields["custom-prompt-2"].exists)
        XCTAssertFalse(app.textFields["custom-prompt-3"].exists)

        app.textFields["custom-prompt-1"].tap()
        app.textFields["custom-prompt-1"].typeText("出门前")
        app.textFields["custom-prompt-2"].tap()
        app.textFields["custom-prompt-2"].typeText("回家以后")
        let use = app.buttons["use-these-moments"]
        XCTAssertTrue(use.isEnabled)
        use.tap()

        // Back on the page, folded to one row.
        let summary = app.buttons["composer-list-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("2"))
        XCTAssertTrue(app.buttons["write-own-entry"].isSelected)
    }
}
