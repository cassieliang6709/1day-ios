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
        // The three fields added when pinch/rotate/colour shipped. Their
        // defaults have to be "exactly how it used to look", or every caption
        // in every existing story moves the day the app updates.
        XCTAssertEqual(CaptionSticker.default.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(CaptionSticker.default.angle, 0, accuracy: 0.0001)
        XCTAssertEqual(CaptionSticker.default.tint, .white)
    }

    /// Same reason the position is clamped: a runaway pinch or twist leaves a
    /// caption unreadable, and there is no reset button on the review screen.
    func testStickerClampsSizeAndAngle() {
        let tiny = CaptionSticker(x: 0.5, y: 0.5, style: .outline, scale: 0.01, angle: -400)
        XCTAssertEqual(tiny.scale, 0.55, accuracy: 0.0001)
        XCTAssertEqual(tiny.angle, -35, accuracy: 0.0001)

        let huge = CaptionSticker(x: 0.5, y: 0.5, style: .outline, scale: 40, angle: 91)
        XCTAssertEqual(huge.scale, 2.2, accuracy: 0.0001)
        XCTAssertEqual(huge.angle, 35, accuracy: 0.0001)

        // A gesture that divided by zero must not poison the stored card.
        // Non-finite falls back to "as it was", not to the clamp: infinity is
        // not a very large rotation, it's the absence of a usable one.
        let broken = CaptionSticker(
            x: 0.5, y: 0.5, style: .outline, scale: .nan, angle: .infinity)
        XCTAssertEqual(broken.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(broken.angle, 0, accuracy: 0.0001)
    }

    /// A sticker saved before scale/angle/tint existed decodes to the values
    /// that reproduce what it looked like, rather than throwing the card away.
    func testStickerDecodesWithoutTheFieldsAddedLater() throws {
        let legacy = Data(#"{"x":0.3,"y":0.6,"style":"band"}"#.utf8)
        let sticker = try JSONDecoder().decode(CaptionSticker.self, from: legacy)
        XCTAssertEqual(sticker.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(sticker.style, .band)
        XCTAssertEqual(sticker.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(sticker.angle, 0, accuracy: 0.0001)
        XCTAssertEqual(sticker.tint, .white)
    }

    /// A colour this version doesn't know is a colour from a later one. Draw
    /// the words in white; don't drop the sticker.
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

    /// A room synced by a phone from before pinch/rotate/colour sends three
    /// parts. That is a whole sticker, not a broken one.
    func testThreePartCloudValueIsStillAWholeSticker() throws {
        let sticker = try XCTUnwrap(CaptionSticker(cloudValue: "0.4,0.7,band"))
        XCTAssertEqual(sticker.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(sticker.style, .band)
        XCTAssertEqual(sticker.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(sticker.tint, .white)

        // And the reverse: a six-part value with an unreadable extra field
        // keeps the position rather than dropping everything.
        let partial = try XCTUnwrap(CaptionSticker(cloudValue: "0.4,0.7,band,big,sideways,neon"))
        XCTAssertEqual(partial.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(partial.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(partial.angle, 0, accuracy: 0.0001)
        XCTAssertEqual(partial.tint, .white)

        // Four or five parts is a value nothing writes — reject it rather than
        // guessing which fields are missing.
        XCTAssertNil(CaptionSticker(cloudValue: "0.4,0.7,band,1.2"))
    }

    // MARK: - Reaction recents

    /// The picker leads with what this person actually reaches for, and the
    /// six built-ins fill in behind. Re-using an emoji moves it to the front
    /// rather than adding it twice.
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

    /// No duplicates between the two halves of the picker, and the defaults
    /// are still all reachable when the history is empty.
    func testReactionSuggestionsNeverRepeatADefault() {
        XCTAssertEqual(
            ClipReactionRecents.suggestions(recents: []), ClipReaction.palette)

        let mixed = ClipReactionRecents.suggestions(recents: ["🧋", "🔥"])
        XCTAssertEqual(mixed.prefix(2).map { $0 }, ["🧋", "🔥"])
        XCTAssertEqual(Set(mixed).count, mixed.count)
        XCTAssertTrue(ClipReaction.palette.allSatisfy(mixed.contains))
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
