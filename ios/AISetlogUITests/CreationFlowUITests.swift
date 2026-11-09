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

    /// 我的's 新建 is today's plan: a name and the list, nothing to choose
    /// between — no 按时间拍, no 自己拍 / 和朋友一起拍 (that's the 朋友 tab).
    func testPlanComposerIsANameAndAList() throws {
        app.launch()
        app.openPersonalLibrary()
        openComposer()

        let summary = app.buttons["composer-list-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["by-time-entry"].exists)
        XCTAssertFalse(app.buttons["write-own-entry"].exists)
        XCTAssertFalse(app.buttons["company-solo"].exists)
        XCTAssertFalse(app.buttons["company-with-friends"].exists)
        XCTAssertFalse(app.buttons["plan-seven-day"].exists)
        XCTAssertFalse(app.buttons["templates-entry"].exists)
        // No list yet: nothing to start.
        XCTAssertFalse(app.buttons["composer-start"].isEnabled)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Plan composer"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWriteListOpensOneEditorWithTwoBlankRows() throws {
        app.launch()
        app.openPersonalLibrary()
        openComposer()

        let list = app.buttons["composer-list-summary"]
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
        XCTAssertTrue(app.buttons["composer-start"].isEnabled)
    }

    /// Today's plan sits beside the mood on 我的, one row per item; and once
    /// there is a plan, 新建 opens it instead of a second one.
    func testTodaysPlanSitsBesideTheMoodAndThereIsOnlyOne() throws {
        app.launch()
        app.openPersonalLibrary()
        openComposer()
        let list = app.buttons["composer-list-summary"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        list.tap()
        XCTAssertTrue(app.textFields["custom-prompt-1"].waitForExistence(timeout: 15))
        app.textFields["custom-prompt-1"].tap()
        app.textFields["custom-prompt-1"].typeText("早餐")
        app.textFields["custom-prompt-2"].tap()
        app.textFields["custom-prompt-2"].typeText("晚饭")
        app.buttons["use-these-moments"].tap()
        let start = app.buttons["composer-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let back = app.buttons["room-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        back.tap()

        let plan = app.descendants(matching: .any)["today-plan-card"]
        XCTAssertTrue(plan.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["mood-today-card"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "today-plan-item").count, 2)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Mood beside today's plan"
        attachment.lifetime = .keepAlways
        add(attachment)

        // A second 新建 today opens the same plan.
        app.buttons["home-compose"].tap()
        XCTAssertTrue(app.buttons["room-back"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["composer-list-summary"].exists)

        // Leave no plan behind: the app's data outlives this test, and with a
        // plan today every later 新建 would open it instead of the composer.
        app.buttons["更多"].tap()
        let delete = app.buttons["删除选题"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        let confirm = app.buttons.matching(identifier: "删除选题").element(boundBy: 0)
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.buttons["home-compose"].waitForExistence(timeout: 15))
    }
}
