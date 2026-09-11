import XCTest
@testable import AISetlog

final class ClipCaptionSelectionTests: XCTestCase {
    func testFriendKeepsOwnTextEvenWhenLocalCardHasCaption() {
        XCTAssertEqual(ClipCaptionSelection.text(isMine: false, hasLiveCard: true,
                                                liveText: "Alice", snapshotText: "Bob"), "Bob")
        XCTAssertNil(ClipCaptionSelection.text(isMine: false, hasLiveCard: true,
                                               liveText: "Alice", snapshotText: nil))
    }

    func testOwnEditsAndExplicitClearBeatOldDeckSnapshot() {
        XCTAssertEqual(ClipCaptionSelection.text(isMine: true, hasLiveCard: true,
                                                liveText: "edited", snapshotText: "old"), "edited")
        XCTAssertNil(ClipCaptionSelection.text(isMine: true, hasLiveCard: true,
                                               liveText: nil, snapshotText: "old"))
        XCTAssertEqual(ClipCaptionSelection.text(isMine: true, hasLiveCard: true,
                                                liveText: "", snapshotText: "old"), "")
    }

    func testStandalonePreviewPreservesVerbatimSnapshot() {
        let text = "我的 subtitle 🌙\nsecond line"
        XCTAssertEqual(ClipCaptionSelection.text(isMine: true, hasLiveCard: false,
                                                liveText: nil, snapshotText: text), text)
    }
}
