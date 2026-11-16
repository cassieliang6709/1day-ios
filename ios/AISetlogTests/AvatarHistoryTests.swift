import XCTest
import UIKit
@testable import AISetlog

@MainActor
final class AvatarHistoryTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-history-\(UUID())")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func png(_ color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private func store() -> AvatarStore { AvatarStore(fileURL: dir.appendingPathComponent("me.png")) }

    func testTheReplacedAvatarIsKept() {
        let s = store()
        s.save(pngData: png(.red))
        XCTAssertTrue(s.history.isEmpty, "the first avatar replaces nothing")
        s.save(pngData: png(.blue))
        XCTAssertEqual(s.history.count, 1)
        XCTAssertEqual(try Data(contentsOf: s.history[0]), png(.red))
    }

    func testSavingTheSamePictureAgainAddsNothing() {
        let s = store()
        s.save(pngData: png(.red))
        s.save(pngData: png(.red))
        XCTAssertTrue(s.history.isEmpty)
    }

    func testRestoringSwapsCurrentAndHistory() {
        let s = store()
        s.save(pngData: png(.red))
        s.save(pngData: png(.blue))
        s.restore(s.history[0])
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("me.png")), png(.red))
        XCTAssertEqual(s.history.count, 1, "red left history, blue went in")
        XCTAssertEqual(try Data(contentsOf: s.history[0]), png(.blue))
    }

    func testHistoryIsCappedAndSurvivesARelaunch() {
        let s = store()
        let colors: [UIColor] = (0...(AvatarStore.historyLimit + 2)).map {
            UIColor(hue: CGFloat($0) / 20, saturation: 1, brightness: 1, alpha: 1)
        }
        for color in colors { s.save(pngData: png(color)); usleep(2000) }
        XCTAssertEqual(s.history.count, AvatarStore.historyLimit)
        XCTAssertEqual(store().history.count, AvatarStore.historyLimit)
    }

    func testRemovingTheAccountClearsHistory() {
        let s = store()
        s.save(pngData: png(.red))
        s.save(pngData: png(.blue))
        s.remove()
        XCTAssertTrue(s.history.isEmpty)
        XCTAssertTrue(store().history.isEmpty)
    }
}
