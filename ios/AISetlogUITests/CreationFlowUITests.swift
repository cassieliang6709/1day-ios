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

    private func openComposer() {
        let compose = app.buttons["home-compose"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15), "新建 button missing")
        compose.tap()
    }

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

        let summary = app.buttons["composer-list-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(summary.label.contains("2"))
        XCTAssertTrue(app.buttons["composer-start"].isEnabled)
    }

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

        app.buttons["home-compose"].tap()
        XCTAssertTrue(app.buttons["room-back"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["composer-list-summary"].exists)

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
