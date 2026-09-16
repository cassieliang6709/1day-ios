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

    // MARK: - The sticker

    /// A sticker dragged off the frame is a caption nobody can read and no
    /// gesture can reach, so the position is clamped rather than trusted.
    func testStickerClampsToTheFrameItSitsOn() {
        let low = CaptionSticker(x: -3, y: -0.2, style: .band)
        XCTAssertEqual(low.x, 0.08, accuracy: 0.0001)
        XCTAssertEqual(low.y, 0.08, accuracy: 0.0001)

        let high = CaptionSticker(x: 1.4, y: 99, style: .band)
        XCTAssertEqual(high.x, 0.92, accuracy: 0.0001)
        XCTAssertEqual(high.y, 0.92, accuracy: 0.0001)

        let inside = CaptionSticker(x: 0.3, y: 0.7, style: .headline)
        XCTAssertEqual(inside.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(inside.y, 0.7, accuracy: 0.0001)
    }

    /// Where every caption was burned before it could be moved. A story saved
    /// back then has no sticker at all, and must not move under its owner.
    func testDefaultIsWhereCaptionsUsedToBeBurned() {
        XCTAssertEqual(CaptionSticker.default.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(CaptionSticker.default.y, 0.43, accuracy: 0.0001)
        XCTAssertEqual(CaptionSticker.default.style, .outline)
    }

    func testStickerSurvivesACloudRoundTripAndRejectsRubbish() {
        let sticker = CaptionSticker(x: 0.25, y: 0.8, style: .headline)
        let restored = CaptionSticker(cloudValue: sticker.cloudValue)
        XCTAssertEqual(restored, sticker)

        XCTAssertNil(CaptionSticker(cloudValue: ""))
        XCTAssertNil(CaptionSticker(cloudValue: "0.5,0.5"))
        XCTAssertNil(CaptionSticker(cloudValue: "0.5,0.5,graffiti"))
        XCTAssertNil(CaptionSticker(cloudValue: "left,0.5,band"))
    }

    /// A card written by a later version names a style this one doesn't have.
    /// Dropping the card over it would lose a clip; the words are what matter.
    func testUnknownStyleDecodesAsTheDefaultStyleRatherThanThrowing() throws {
        let json = #"{"x":0.4,"y":0.6,"style":"neon"}"#.data(using: .utf8)!
        let sticker = try JSONDecoder().decode(CaptionSticker.self, from: json)
        XCTAssertEqual(sticker.style, .outline)
        XCTAssertEqual(sticker.x, 0.4, accuracy: 0.0001)
    }

    /// A card saved before stickers existed decodes, and stays unmoved.
    func testCardWithoutAStickerStillDecodes() throws {
        let json = #"{"day":2,"overlayText":"hello"}"#.data(using: .utf8)!
        let card = try JSONDecoder().decode(DayCard.self, from: json)
        XCTAssertNil(card.captionSticker)
        XCTAssertEqual(card.overlayText, "hello")
    }

    /// Deleting the words deletes where they were. Otherwise a caption thrown
    /// away and typed again comes back wherever the last one was dragged to,
    /// which reads as the app remembering something you deleted.
    @MainActor
    func testClearingTheWordsClearsTheSticker() throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        let store = ChallengeStore(
            repository: files, fileStore: files, coverStore: files, effects: .isolated)
        let story = store.create(title: "Caption story")

        store.updateOverlayText("golden hour", day: 1, challengeID: story.id)
        store.updateCaptionSticker(
            CaptionSticker(x: 0.2, y: 0.9, style: .band), day: 1, challengeID: story.id)
        XCTAssertEqual(card(store, story.id)?.captionSticker?.style, .band)

        store.updateOverlayText("   ", day: 1, challengeID: story.id)
        XCTAssertNil(card(store, story.id)?.overlayText)
        XCTAssertNil(card(store, story.id)?.captionSticker)
    }

    @MainActor
    private func card(_ store: ChallengeStore, _ id: UUID) -> DayCard? {
        store.challenge(id)?.cards.first { $0.day == 1 }
    }
}
