import XCTest

final class LocalFormalRoomUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
            "-demoEntries", "YES",
        ]
        app.launch()
        app.openPersonalLibrary()
        return app
    }

    func testFormalRoomChatAndThreeMemberSwitch() {
        let app = launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: UITestWait.media))
        XCTAssertTrue(app.staticTexts["local-room-notice"].exists)
        capture(app, "Formal two-member StoryTimelineView")
        app.buttons["room-chat"].tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["chat-local-demo-banner"].exists)
        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.exists)
        input.tap()
        input.typeText("local UI message")
        app.buttons["chat-send"].tap()
        XCTAssertTrue(app.staticTexts["local UI message"].waitForExistence(timeout: 15))
        app.buttons["chat-done"].tap()

        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: 15))
        app.segmentedControls["local-room-members"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: UITestWait.media))
        app.buttons["room-chat"].tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["local UI message"].exists)
        app.buttons["chat-done"].tap()
        capture(app, "Formal three-member StoryTimelineView")
        app.buttons["room-back"].tap()
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        XCTAssertTrue(demo.isHittable)
        demo.tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: UITestWait.media))
        XCTAssertTrue(app.segmentedControls["local-room-members"].buttons.element(boundBy: 0).isSelected)
    }

    func testRoomFacePicksAndUnpicks() {
        let app = launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: UITestWait.media))
        let face = app.buttons.matching(identifier: "room-story-face")
            .matching(NSPredicate(format: "isEnabled == true")).firstMatch
        XCTAssertTrue(face.waitForExistence(timeout: 15), "somebody filmed today")
        face.tap()
        XCTAssertTrue(face.isSelected)
        capture(app, "One person picked")
        face.tap()
        XCTAssertFalse(face.isSelected)
    }

    func testFormalRoomFilmRenders() {
        let app = launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()
        let more = app.buttons["room-more"]
        XCTAssertTrue(more.waitForExistence(timeout: UITestWait.media))
        more.tap()
        app.buttons["room-make-vlog"].tap()
        XCTAssertTrue(app.buttons["film-adjust"].waitForExistence(timeout: UITestWait.media))
        XCTAssertFalse(app.buttons["film-save"].isEnabled)
        XCTAssertFalse(app.buttons["film-share"].isEnabled)
        capture(app, "Production FilmView with local real synthesis")
    }

    func testFormalRoomFilmFilterAndHold() {
        let app = launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()
        let more = app.buttons["room-more"]
        XCTAssertTrue(more.waitForExistence(timeout: UITestWait.media))
        more.tap()
        app.buttons["room-make-vlog"].tap()

        let person = app.buttons["film-person-0"]
        XCTAssertTrue(person.waitForExistence(timeout: UITestWait.media))
        XCTAssertTrue(app.buttons["film-person-1"].exists, "one face per person in the room")
        capture(app, "Film page with the people row")

        person.tap()
        let hold = app.switches["film-clip-hold-0"]
        XCTAssertTrue(hold.waitForExistence(timeout: 15))
        hold.switches.firstMatch.tap()
        XCTAssertTrue(app.sliders["film-clip-hold-frame-0"].waitForExistence(timeout: 15))
        app.sliders["film-clip-hold-frame-0"].adjust(toNormalizedSliderPosition: 0.5)
        capture(app, "One person's takes with the first held")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["film-filter-toggle-1"].waitForExistence(timeout: 15))
        capture(app, "Filter sheet, everyone")
        app.buttons["film-filter-apply"].tap()

        XCTAssertTrue(app.buttons["film-adjust"].waitForExistence(timeout: UITestWait.media))
        XCTAssertTrue(app.buttons["film-person-0"].waitForExistence(timeout: 15))
        capture(app, "Film page after applying a hold")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
