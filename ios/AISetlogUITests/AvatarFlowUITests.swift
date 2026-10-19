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
        XCTAssertTrue(app.staticTexts["给我看看你"].exists)
        XCTAssertTrue(app.staticTexts["拍一张，或从相册挑。"].exists)
        XCTAssertTrue(app.staticTexts["正面照效果最好"].exists)
        XCTAssertTrue(app.buttons["avatar-take-photo"].exists)
        XCTAssertTrue(app.buttons["avatar-pick-photo"].exists)
        capture(app, "Avatar upload")

        app.buttons["avatar-skip"].tap()
        XCTAssertTrue(app.buttons["avatar-skip"].waitForNonExistence(timeout: 10))
    }

    func testAPhotoBecomesAnAvatarThroughTheThreeSteps() throws {
        let path = try Self.writeSample()
        let app = launch(sample: path)

        XCTAssertTrue(app.staticTexts["正在画你。"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["几秒钟。"].exists)
        capture(app, "Avatar generating")

        let confirm = app.buttons["avatar-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 90))
        XCTAssertTrue(app.staticTexts["画好了。这是你。"].exists)
        XCTAssertTrue(app.buttons["avatar-redraw"].exists)
        XCTAssertTrue(app.images["avatar-result"].exists)
        capture(app, "Avatar confirm")

        confirm.tap()
        XCTAssertTrue(app.staticTexts["好了，去记今天。"].waitForExistence(timeout: 10))
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 15))
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
