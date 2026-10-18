import XCTest

/// Navigation and isolated-data UI evidence, not proof of moving video pixels.
///
/// Split in two as of 1.3, and the reason is worth writing down because it was
/// misdiagnosed once already.
///
/// The film assertion in here used to time out on CI and pass on a developer
/// Mac, and it looked like `FilmView` hanging — it *was* also hanging, on a
/// separate and real bug (three `return` paths that left a spinner nothing
/// could finish; fixed, see `FilmRenderOutcome`). But that was not why this
/// test failed. With the hang fixed, CI still burned the whole 240s ceiling
/// here and the log shows why: zero `[stitch] exporting` lines and zero
/// `[stitch] failed` lines in the four and a half minutes the test ran. The
/// stitch had not reached its export — it was still inside `filteredClips`,
/// the per-clip look pass, which on a runner with no GPU is software Core
/// Image over every frame of every take.
///
/// `UITestWait` already records the measurements: the two- and three-member
/// compositor costs 141.5s on the runner *with no UI on top of it*, and the
/// heaviest media test in the suite costs 208.7s. A three-member
/// `friendsTogether` film behind a UI test does not fit under 240s there, and
/// raising the ceiling again would only move the number the test is really
/// measuring — which is the runner, not the app.
///
/// So the film lives in its own test now, skipped on CI (see
/// `.github/workflows/ios-tests.yml`) and run on a Mac. Everything this suite
/// is actually named for — chat, room isolation, the member switch — stays on
/// CI, where it costs 92 seconds and passes.
final class LocalFormalRoomUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
            // The demo entries this suite navigates through are opt-in as of
            // 1.3 — see `DemoEntries` in the app target. A UI test runs in its
            // own process, so the flag is spelled out rather than referenced.
            // Without it the home screen has no 房间演示 button and the camera
            // has no 示例片段, and on a runner with no camera there is then no
            // way to get footage anywhere.
            "-demoEntries", "YES",
        ]
        app.launch()
        return app
    }

    /// Chat, room isolation, and the member switch. No video is rendered.
    func testFormalRoomChatAndThreeMemberSwitch() {
        let app = launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()
        XCTAssertTrue(app.buttons["room-make-vlog"].waitForExistence(timeout: UITestWait.media))
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

        // The shell's member selector remains outside the navigation stack;
        // changing it replaces only this local session and its navigation state.
        XCTAssertTrue(app.buttons["room-make-vlog"].waitForExistence(timeout: 15))
        app.segmentedControls["local-room-members"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["room-make-vlog"].waitForExistence(timeout: UITestWait.media))
        app.buttons["room-chat"].tap()
        XCTAssertTrue(app.staticTexts["今天的故事拍什么？"].waitForExistence(timeout: 15))
        // The three-member session is a different room: the message typed into
        // the two-member one must not be in it.
        XCTAssertFalse(app.staticTexts["local UI message"].exists)
        app.buttons["chat-done"].tap()
        capture(app, "Formal three-member StoryTimelineView")
        app.buttons["room-back"].tap()
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        XCTAssertTrue(demo.isHittable)
        demo.tap()
        XCTAssertTrue(app.buttons["room-make-vlog"].waitForExistence(timeout: UITestWait.media))
        XCTAssertTrue(app.segmentedControls["local-room-members"].buttons.element(boundBy: 0).isSelected)
    }

    /// The film actually assembling, from the production `FilmView` over a
    /// local demo room's real clips.
    ///
    /// **Skipped on CI.** See this type's note: the stitch's look pass alone
    /// outruns the 240s ceiling on a GPU-less runner, so on CI this measures
    /// the machine. On a Mac it takes about 40 seconds.
    ///
    /// What it pins that no unit test can: that 「生成 vlog」 reaches a rendered
    /// film through the real navigation stack, and that 保存 and 分享 are
    /// disabled for a demo room — a demo must not be able to write to the photo
    /// library or leave the device.
    func testFormalRoomFilmRenders() {
        let app = launch()
        let demo = app.buttons["home-room-demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 15))
        demo.tap()
        let film = app.buttons["room-make-vlog"]
        XCTAssertTrue(film.waitForExistence(timeout: UITestWait.media))
        film.tap()
        XCTAssertTrue(app.buttons["film-adjust"].waitForExistence(timeout: UITestWait.media))
        XCTAssertFalse(app.buttons["film-save"].isEnabled)
        XCTAssertFalse(app.buttons["film-share"].isEnabled)
        capture(app, "Production FilmView with local real synthesis")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
