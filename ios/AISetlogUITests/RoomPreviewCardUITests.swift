import XCTest

final class RoomPreviewCardUITests: XCTestCase {
    func testRoomPreviewCardsOpenAndReturnToTheList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese",
                               "-debugSeedRoomPreviews", "YES"]
        app.launch()
        let cards = app.buttons.matching(identifier: "room-preview-card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["rooms-personal"].exists)
        XCTAssertTrue(cards.firstMatch.label.contains("周末放映室"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "room-content-preview-cards"
        shot.lifetime = .keepAlways
        add(shot)
        cards.firstMatch.tap()
        XCTAssertTrue(app.buttons["room-back"].waitForExistence(timeout: 15))
        app.buttons["room-back"].tap()
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
    }
}
