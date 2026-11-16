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

    func testDefaultIsWhereCaptionsUsedToBeBurned() {
        XCTAssertEqual(CaptionSticker.default.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(CaptionSticker.default.y, 0.43, accuracy: 0.0001)
        XCTAssertEqual(CaptionSticker.default.style, .outline)
        XCTAssertEqual(CaptionSticker.default.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(CaptionSticker.default.angle, 0, accuracy: 0.0001)
        XCTAssertEqual(CaptionSticker.default.tint, .white)
    }

    func testStickerClampsSizeAndAngle() {
        let tiny = CaptionSticker(x: 0.5, y: 0.5, style: .outline, scale: 0.01, angle: -400)
        XCTAssertEqual(tiny.scale, 0.55, accuracy: 0.0001)
        XCTAssertEqual(tiny.angle, -35, accuracy: 0.0001)

        let huge = CaptionSticker(x: 0.5, y: 0.5, style: .outline, scale: 40, angle: 91)
        XCTAssertEqual(huge.scale, 2.2, accuracy: 0.0001)
        XCTAssertEqual(huge.angle, 35, accuracy: 0.0001)

        let broken = CaptionSticker(
            x: 0.5, y: 0.5, style: .outline, scale: .nan, angle: .infinity)
        XCTAssertEqual(broken.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(broken.angle, 0, accuracy: 0.0001)
    }

    func testStickerDecodesWithoutTheFieldsAddedLater() throws {
        let legacy = Data(#"{"x":0.3,"y":0.6,"style":"band"}"#.utf8)
        let sticker = try JSONDecoder().decode(CaptionSticker.self, from: legacy)
        XCTAssertEqual(sticker.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(sticker.style, .band)
        XCTAssertEqual(sticker.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(sticker.angle, 0, accuracy: 0.0001)
        XCTAssertEqual(sticker.tint, .white)
    }

    func testUnknownTintFallsBackToWhite() throws {
        let future = Data(#"{"x":0.5,"y":0.5,"style":"outline","tint":"neon"}"#.utf8)
        let sticker = try JSONDecoder().decode(CaptionSticker.self, from: future)
        XCTAssertEqual(sticker.tint, .white)
    }

    func testStickerSurvivesACloudRoundTripAndRejectsRubbish() {
        let sticker = CaptionSticker(
            x: 0.25, y: 0.8, style: .headline, scale: 1.6, angle: -12, tint: .mint)
        let restored = CaptionSticker(cloudValue: sticker.cloudValue)
        XCTAssertEqual(restored, sticker)

        XCTAssertNil(CaptionSticker(cloudValue: ""))
        XCTAssertNil(CaptionSticker(cloudValue: "0.5,0.5"))
        XCTAssertNil(CaptionSticker(cloudValue: "0.5,0.5,graffiti"))
        XCTAssertNil(CaptionSticker(cloudValue: "left,0.5,band"))
    }

    func testThreePartCloudValueIsStillAWholeSticker() throws {
        let sticker = try XCTUnwrap(CaptionSticker(cloudValue: "0.4,0.7,band"))
        XCTAssertEqual(sticker.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(sticker.style, .band)
        XCTAssertEqual(sticker.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(sticker.tint, .white)

        let partial = try XCTUnwrap(CaptionSticker(cloudValue: "0.4,0.7,band,big,sideways,neon"))
        XCTAssertEqual(partial.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(partial.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(partial.angle, 0, accuracy: 0.0001)
        XCTAssertEqual(partial.tint, .white)

        XCTAssertNil(CaptionSticker(cloudValue: "0.4,0.7,band,1.2"))
    }


    func testReactionRecentsAreMostRecentFirstDedupedAndCapped() {
        var recents: [String] = []
        for emoji in ["❤️", "🔥", "😂"] {
            recents = ClipReactionRecents.adding(emoji, to: recents)
        }
        XCTAssertEqual(recents, ["😂", "🔥", "❤️"])

        recents = ClipReactionRecents.adding("❤️", to: recents)
        XCTAssertEqual(recents, ["❤️", "😂", "🔥"])

        for emoji in ["🐳", "🍜", "🌙", "🧋", "🪴", "🎧", "🧃"] {
            recents = ClipReactionRecents.adding(emoji, to: recents)
        }
        XCTAssertEqual(recents.count, ClipReactionRecents.limit)
        XCTAssertEqual(recents.first, "🧃")
    }

    func testReactionSuggestionsNeverRepeatADefault() {
        XCTAssertEqual(
            ClipReactionRecents.suggestions(recents: []), ClipReaction.palette)

        let mixed = ClipReactionRecents.suggestions(recents: ["🧋", "🔥"])
        XCTAssertEqual(mixed.prefix(2).map { $0 }, ["🧋", "🔥"])
        XCTAssertEqual(Set(mixed).count, mixed.count)
        XCTAssertTrue(ClipReaction.palette.allSatisfy(mixed.contains))
    }

    func testUnknownStyleDecodesAsTheDefaultStyleRatherThanThrowing() throws {
        let json = #"{"x":0.4,"y":0.6,"style":"neon"}"#.data(using: .utf8)!
        let sticker = try JSONDecoder().decode(CaptionSticker.self, from: json)
        XCTAssertEqual(sticker.style, .outline)
        XCTAssertEqual(sticker.x, 0.4, accuracy: 0.0001)
    }

    func testCardWithoutAStickerStillDecodes() throws {
        let json = #"{"day":2,"overlayText":"hello"}"#.data(using: .utf8)!
        let card = try JSONDecoder().decode(DayCard.self, from: json)
        XCTAssertNil(card.captionSticker)
        XCTAssertEqual(card.overlayText, "hello")
    }

    @MainActor
    func testClearingTheWordsClearsTheSticker() throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        let store = ChallengeStore(
            repository: files, fileStore: files, effects: .isolated)
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
