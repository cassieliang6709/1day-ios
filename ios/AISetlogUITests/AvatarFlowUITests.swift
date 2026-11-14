import UIKit
import XCTest

/// The avatar's three steps, opened straight from launch with
/// `-debugAvatarFlow YES` (the Simulator has no camera, and its photo library
/// has no faces). `-debugAvatarSample` hands the flow a picture; with no face
/// in it the Vision path still cuts out the middle and decorates it, which is
/// enough to walk upload → generating → confirm.
final class AvatarFlowUITests: XCTestCase {
    private func launch(sample: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed.v1", "YES",
            "-appLanguage", "chinese",
            "-debugAvatarFlow", "YES",
            "-debugAvatarForceFallback", "YES",
        ]
        if let sample { app.launchArguments += ["-debugAvatarSample", sample] }
        app.launch()
        return app
    }

    func testUploadStepSaysWhatTheSpecSaysAndCanBeSkipped() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["用一张照片，画一个你。"].waitForExistence(timeout: 30))
        // Copy audit: the title, the second line and the hint are gone.
        XCTAssertFalse(app.staticTexts["给我看看你"].exists)
        XCTAssertFalse(app.staticTexts["正面照效果最好"].exists)
        XCTAssertTrue(app.buttons["avatar-take-photo"].exists)
        XCTAssertTrue(app.buttons["avatar-pick-photo"].exists)
        capture(app, "Avatar upload")

        app.buttons["avatar-skip"].tap()
        XCTAssertTrue(app.buttons["avatar-skip"].waitForNonExistence(timeout: 10))
    }

    func testAPhotoBecomesAnAvatarThroughTheThreeSteps() throws {
        let path = try Self.writeSample()
        try? FileManager.default.removeItem(atPath: Self.tracePath)
        let app = launch(sample: path)

        XCTAssertTrue(app.staticTexts["正在画你"].waitForExistence(timeout: 30))
        capture(app, "Avatar generating")

        let confirm = app.buttons["avatar-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 90))
        XCTAssertTrue(app.staticTexts["这是你"].exists)
        XCTAssertTrue(app.buttons["avatar-redraw"].exists)
        XCTAssertTrue(app.images["avatar-result"].exists)
        capture(app, "Avatar confirm")

        confirm.tap()
        // On the runner the synthesized tap is now and then cancelled
        // underneath the app: the window sees the touch begin and then
        // `touchesCancelled`, never `touchesEnded`, so the Button rightly does
        // nothing (runs 43351505237 and 43357115667). A person would tap
        // again; so does this, once, and only when the app's trace shows that
        // a cancelled touch is what happened. A touch that ended without
        // reaching accept() still fails.
        if Self.waitForTapOutcome() == .cancelled {
            print("[avatar-test] first tap was cancelled under the app, tapping again:\n" + Self.appTrace())
            confirm.tap()
        }
        let closed = confirm.waitForNonExistence(timeout: 15)
        if !closed { dumpFailure(app) }
        XCTAssertTrue(closed)
    }

    // MARK: - Diagnostics

    /// Written by the app (`AvatarFlowTrace`) while `-debugAvatarSample` is set.
    private static let tracePath = "/tmp/1day-uitest-avatar-trace.log"

    enum TapOutcome { case accepted, cancelled, unknown }

    /// What the app logged for the tap on 「就是这样」, waiting a few seconds
    /// for it to say.
    private static func waitForTapOutcome() -> TapOutcome {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let lines = appTrace().split(separator: "\n")
            guard let confirmShown = lines.lastIndex(where: { $0.contains("step generating -> confirm") })
            else { return .unknown }
            let after = lines[confirmShown...]
            if after.contains(where: { $0.contains("accept tapped") }) { return .accepted }
            if after.contains(where: { $0.contains("touch cancelled") }) { return .cancelled }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return .unknown
    }

    private static func appTrace() -> String {
        (try? String(contentsOfFile: tracePath, encoding: .utf8)) ?? "(no trace file)"
    }

    private func dumpFailure(_ app: XCUIApplication) {
        let appTrace = Self.appTrace()
        print("[avatar-test] app trace:\n" + appTrace)
        let tree = app.debugDescription
        print("[avatar-test] app tree:\n" + tree)
        for (name, text) in [("App trace", appTrace), ("App tree", tree)] {
            let attachment = XCTAttachment(string: text)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        capture(app, "Avatar still open")
    }

    /// A plain drawn "face" — a skin-coloured oval on a coloured background.
    /// Written where the app (another Simulator process on this Mac) can read it.
    private static func writeSample() throws -> String {
        let size = CGSize(width: 600, height: 800)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.96, green: 0.8, blue: 0.68, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 150, y: 180, width: 300, height: 380))
            UIColor.darkGray.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 230, y: 320, width: 36, height: 24))
            ctx.cgContext.fillEllipse(in: CGRect(x: 334, y: 320, width: 36, height: 24))
        }
        let path = "/tmp/1day-uitest-avatar-sample.png"
        try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: path))
        return path
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
