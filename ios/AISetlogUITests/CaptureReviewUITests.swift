import XCTest

final class CaptureReviewUITests: XCTestCase {
    private func capture(landscape: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese",
                               "-simulatedCamera", "YES"]
        app.launch()
        let camera = app.buttons["tab-camera"]
        XCTAssertTrue(camera.waitForExistence(timeout: 15))
        camera.tap()
        let sideways = app.buttons["camera-sideways-toggle"]
        XCTAssertTrue(sideways.waitForExistence(timeout: 15))
        if landscape { sideways.tap() }
        let shutter = app.buttons["camera-shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        shutter.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-review-frame"].waitForExistence(timeout: UITestWait.media))
        return app
    }

    func testLandscapeTakeIsReviewedInAnUprightWideFrame() {
        let app = capture(landscape: true)
        let frame = app.descendants(matching: .any)["capture-review-frame"].frame
        XCTAssertGreaterThan(frame.width, frame.height)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "landscape-send-preview"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["camera-close"].tap()
        XCTAssertTrue(app.buttons["rooms-personal"].waitForExistence(timeout: 10))
    }

    func testPortraitTakeKeepsItsTallFrame() {
        let app = capture(landscape: false)
        let frame = app.descendants(matching: .any)["capture-review-frame"].frame
        XCTAssertLessThan(frame.width, frame.height)
    }
}
