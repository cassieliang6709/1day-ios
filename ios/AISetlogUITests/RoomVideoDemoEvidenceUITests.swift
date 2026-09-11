import XCTest

/// Captures evidence, not a claim that the displayed video is correct.
final class RoomVideoDemoEvidenceUITests: XCTestCase {
    func testCaptureDemoAfterMediaPreparation() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed.v1", "YES", "-appLanguage", "chinese", "-roomPlaybackDiagnostics"]
        app.launch()
        let entry = app.buttons["home-room-demo"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        let three = app.buttons["三人"]
        XCTAssertTrue(three.waitForExistence(timeout: 8))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: three)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        let video = app.images.matching(identifier: "room-demo-decoded-video").firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 8))
        let initialFrames = video.value as? String
        let advancing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = video.value as? String else { return false }
            return value.contains("frames=") && value != initialFrames
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 8), .completed)
        XCTAssertTrue(app.buttons["自动"].exists)
        let composite = app.images.matching(identifier: "room-demo-decoded-video").element(boundBy: 2)
        XCTAssertTrue(composite.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(composite.frame.width, composite.frame.height,
                             "Default portrait samples must produce a landscape canvas")
        let beforeLoop = video.value as? String
        XCTAssertNotNil(beforeLoop)
        for index in 0..<3 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Demo prepared frame \(index)"
            shot.lifetime = .keepAlways
            add(shot)
            Thread.sleep(forTimeInterval: 2)
        }
        let afterLoop = video.value as? String
        XCTAssertNotEqual(beforeLoop, afterLoop)
        three.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: three)], timeout: 20), .completed)
        app.buttons["横版"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: three)], timeout: 20), .completed)
        app.scrollViews.firstMatch.swipeUp()
        let together = XCTAttachment(screenshot: app.screenshot())
        together.name = "Three members landscape composite"
        together.lifetime = .keepAlways
        add(together)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Demo playback accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
