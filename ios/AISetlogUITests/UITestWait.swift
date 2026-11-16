import Foundation
import XCTest

enum UITestWait {
    static let media: TimeInterval = 240
}

extension XCUIApplication {
    func openPersonalLibrary() {
        let entry = buttons["rooms-personal"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "Personal library entry missing from Rooms")
        entry.tap()
        XCTAssertTrue(buttons["personal-back"].waitForExistence(timeout: 10))
    }
}
