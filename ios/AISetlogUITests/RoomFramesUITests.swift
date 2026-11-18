import XCTest

final class RoomFramesUITests: XCTestCase {
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

    private func frames(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "room-frame")
    }

    func testOneFramePerMemberAndPersonPage() {
        let app = launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()

        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: UITestWait.media))
        XCTAssertTrue(frames(app).firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(frames(app).count, 2)
        capture(app, "room-frames-2")

        let person = app.buttons.matching(identifier: "room-frame-person").firstMatch
        XCTAssertTrue(person.exists)
        person.tap()
        XCTAssertTrue(app.buttons["room-person-back"].waitForExistence(timeout: 15))
        capture(app, "room-person-page")
        app.buttons["room-person-back"].tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: 15))

        app.segmentedControls["local-room-members"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["room-more"].waitForExistence(timeout: UITestWait.media))
        let three = NSPredicate(format: "count == 3")
        expectation(for: three, evaluatedWith: frames(app))
        waitForExpectations(timeout: UITestWait.media)
        capture(app, "room-frames-3")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
