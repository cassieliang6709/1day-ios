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

        trace("before tap: hittable=\(confirm.isHittable) enabled=\(confirm.isEnabled)")
        confirm.tap()
        trace("tapped")
        let closed = confirm.waitForNonExistence(timeout: 15)
        trace("closed=\(closed)")
        if !closed { dumpFailure(app) } else { printAppTrace() }
        XCTAssertTrue(closed)
    }

    /// TEMPORARY, for finding the flake: the same walk, eight launches.
    func testZZDiagnoseConfirmRepeatedly() throws {
        var failures: [Int] = []
        for attempt in 1...8 {
            let path = try Self.writeSample()
            try? FileManager.default.removeItem(atPath: Self.tracePath)
            let app = launch(sample: path)
            let confirm = app.buttons["avatar-confirm"]
            guard confirm.waitForExistence(timeout: 90) else {
                trace("attempt \(attempt): confirm never appeared")
                failures.append(attempt); dumpFailure(app); continue
            }
            trace("attempt \(attempt) before tap: hittable=\(confirm.isHittable)")
            confirm.tap()
            trace("attempt \(attempt) tapped")
            let closed = confirm.waitForNonExistence(timeout: 15)
            trace("attempt \(attempt) closed=\(closed)")
            if !closed { failures.append(attempt); dumpFailure(app) } else { printAppTrace() }
        }
        XCTAssertEqual(failures, [], "attempts that stayed open")
    }

    // MARK: - Diagnostics

    /// Written by the app (`AvatarFlowTrace`) while `-debugAvatarSample` is set.
    private static let tracePath = "/tmp/1day-uitest-avatar-trace.log"

    private func trace(_ note: String) {
        print(String(format: "[avatar-test] %.3f ", Date().timeIntervalSince1970) + note)
    }

    @discardableResult
    private func printAppTrace() -> String {
        let appTrace = (try? String(contentsOfFile: Self.tracePath, encoding: .utf8)) ?? "(no trace file)"
        print("[avatar-test] app trace:\n" + appTrace)
        return appTrace
    }

    private func dumpFailure(_ app: XCUIApplication) {
        let appTrace = printAppTrace()
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
