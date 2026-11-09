import XCTest

final class RoomNavigationUITests: XCTestCase {
    func testRoomsOpensPersonalLibraryAndCameraWithoutHiddenPageControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese"]
        app.launch()

        XCTAssertTrue(app.buttons["rooms-personal"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["tab-camera"].exists)
        XCTAssertTrue(app.buttons["tab-rooms"].isSelected)
        XCTAssertFalse(app.buttons["home-compose"].exists)
        XCTAssertFalse(app.buttons["personal-back"].exists)

        app.openPersonalLibrary()
        XCTAssertTrue(app.buttons["home-compose"].exists)
        XCTAssertFalse(app.buttons["rooms-personal"].exists)
        XCTAssertFalse(app.buttons["friends-new-room"].exists)
        app.buttons["personal-back"].tap()
        XCTAssertTrue(app.buttons["rooms-personal"].waitForExistence(timeout: 10))

        app.buttons["tab-camera"].tap()
        XCTAssertTrue(app.buttons["camera-close"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["tab-camera"].isSelected)
        XCTAssertFalse(app.buttons["rooms-personal"].exists)
        app.buttons["tab-rooms"].tap()
        XCTAssertTrue(app.buttons["rooms-personal"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["camera-close"].exists)
    }

    func testNewRoomHasAFriendlyDefaultName() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese"]
        app.launch()
        let newRoom = app.buttons["friends-new-room"]
        XCTAssertTrue(newRoom.waitForExistence(timeout: 15))
        newRoom.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "一起的日常")
    }
}
