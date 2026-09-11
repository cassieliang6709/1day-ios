import XCTest
@testable import AISetlog

final class LocalRoomMediaKeyTests: XCTestCase {
    func testStableIdentityDoesNotReuseReplacedMediaOrCaptionCache() {
        func clip(_ file: String, caption: String? = nil) -> DayClip {
            DayClip(day: 1, url: URL(fileURLWithPath: "/tmp/\(file).mov"),
                    authorName: "Member", authorID: "demo", overlayText: caption, key: "stable-id")
        }
        let initial = LocalRoomMediaKey.make(day: 1, clips: [clip("original")])
        XCTAssertEqual(initial, LocalRoomMediaKey.make(day: 1, clips: [clip("original")]))
        XCTAssertNotEqual(initial, LocalRoomMediaKey.make(day: 1, clips: [clip("replacement")]))
        XCTAssertNotEqual(initial, LocalRoomMediaKey.make(day: 1, clips: [clip("original", caption: "字幕 English")]))
        XCTAssertNotEqual(initial, LocalRoomMediaKey.make(day: 2, clips: [clip("original")]))
    }
}
