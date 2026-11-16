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

    func testReRecordingAtTheSamePathInvalidatesTheMoment() {
        let before = DayClip(
            day: 1, url: URL(fileURLWithPath: "/tmp/reused.mov"),
            recordedAt: Date(timeIntervalSince1970: 100), key: "same-record")
        var after = before
        after.recordedAt = Date(timeIntervalSince1970: 101)
        XCTAssertNotEqual(
            LocalRoomMediaKey.make(day: 1, clips: [before]),
            LocalRoomMediaKey.make(day: 1, clips: [after]))
    }

    func testExtraCaptionAndMovingItsStickerInvalidateTheMoment() {
        let before = DayClip(
            day: 1, url: URL(fileURLWithPath: "/tmp/take.mov"),
            captions: [Caption(text: "First"), Caption(text: "Second")])
        let initial = LocalRoomMediaKey.make(day: 1, clips: [before])
        var after = before
        after.captions[1].text = "Edited second caption"
        XCTAssertNotEqual(initial, LocalRoomMediaKey.make(day: 1, clips: [after]))
        after = before
        after.captions[1].sticker = CaptionSticker(x: 0.2, y: 0.3, style: .outline)
        XCTAssertNotEqual(initial, LocalRoomMediaKey.make(day: 1, clips: [after]))
        XCTAssertEqual(initial, LocalRoomMediaKey.make(day: 1, clips: [before]))
        after = before
        after.captions = before.captions.map { Caption(text: $0.text, sticker: $0.sticker) }
        XCTAssertEqual(initial, LocalRoomMediaKey.make(day: 1, clips: [after]),
                       "Rebuilt caption UUIDs must not force a render of identical frames")
    }

    func testPeopleOrderAndBurnedTextArePartOfTheMoment() {
        let alice = DayClip(day: 1, url: URL(fileURLWithPath: "/tmp/a.mov"),
                            authorName: "Alice", key: "a")
        let bob = DayClip(day: 1, url: URL(fileURLWithPath: "/tmp/b.mov"),
                          authorName: "Bob", key: "b")
        let initial = LocalRoomMediaKey.make(day: 1, clips: [alice, bob])
        XCTAssertNotEqual(initial, LocalRoomMediaKey.make(day: 1, clips: [bob, alice]))
        var renamed = alice
        renamed.authorName = "New name"
        renamed.comments = ["Bob: lovely"]
        XCTAssertNotEqual(initial, LocalRoomMediaKey.make(day: 1, clips: [renamed, bob]))
    }
}
