import XCTest
@testable import AISetlog

/// A clip holds a list of captions now. Everything saved before that — on this
/// phone and in the room — has to read as a list of one.
final class CaptionListTests: XCTestCase {

    // MARK: - Old local data

    func testAnOldCardDecodesAsOneCaption() throws {
        let json = #"""
        {"day":2,"overlayText":"hello","captionSticker":{"x":0.2,"y":0.7,"style":"band"},
         "reactions":[],"comments":[]}
        """#
        let card = try JSONDecoder().decode(DayCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.captions.count, 1)
        XCTAssertEqual(card.captions.first?.text, "hello")
        XCTAssertEqual(card.captions.first?.sticker?.style, .band)
        XCTAssertEqual(card.captions.first?.sticker?.x ?? 0, 0.2, accuracy: 0.0001)
        XCTAssertEqual(card.overlayText, "hello")
    }

    func testAnOldCardWithoutWordsHasNoCaptions() throws {
        let json = #"{"day":1,"clipFileName":"day1.mov"}"#
        let card = try JSONDecoder().decode(DayCard.self, from: Data(json.utf8))
        XCTAssertTrue(card.captions.isEmpty)
        XCTAssertNil(card.overlayText)
    }

    func testAnOldExtraTakeDecodesAsOneCaption() throws {
        let id = UUID()
        let json = #"""
        {"day":1,"clipFileName":"day1.mov","moreTakes":[
          {"id":"\#(id.uuidString)","fileName":"day1_x.mov","recordedAt":0,"overlayText":"two"}]}
        """#
        let card = try JSONDecoder().decode(DayCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.moreTakes.first?.id, id)
        XCTAssertEqual(card.moreTakes.first?.captions.map(\.text), ["two"])
        XCTAssertNil(card.moreTakes.first?.captionSticker)
    }

    func testAnOldDraftDecodesAsOneCaption() throws {
        let json = #"""
        {"id":"\#(UUID().uuidString)","fileName":"d.mov","recordedAt":0,
         "orientation":"portrait","overlayText":"傍晚的光","byteSize":12}
        """#
        let draft = try JSONDecoder().decode(ClipDraft.self, from: Data(json.utf8))
        XCTAssertEqual(draft.captions.map(\.text), ["傍晚的光"])
        XCTAssertEqual(draft.byteSize, 12)
    }

    /// A save writes the list, and the first caption again under the old keys,
    /// so an older build reading the same file still shows it.
    func testSavingWritesTheListAndTheOldKeys() throws {
        let sticker = CaptionSticker(x: 0.3, y: 0.3, style: .solid)
        var card = DayCard(day: 1, clipFileName: "day1.mov")
        card.captions = [Caption(text: "one", sticker: sticker), Caption(text: "two")]

        let data = try JSONEncoder().encode(card)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["overlayText"] as? String, "one")
        XCTAssertNotNil(object["captionSticker"])
        XCTAssertEqual((object["captions"] as? [Any])?.count, 2)

        let back = try JSONDecoder().decode(DayCard.self, from: data)
        XCTAssertEqual(back.captions, card.captions)
    }

    // MARK: - The first-caption shims

    func testSettingOverlayTextEditsOrRemovesTheFirstCaption() {
        var card = DayCard(day: 1)
        card.overlayText = "a"
        card.captions.append(Caption(text: "b"))
        card.overlayText = "A"
        XCTAssertEqual(card.captions.map(\.text), ["A", "b"])
        card.overlayText = "  "
        XCTAssertEqual(card.captions.map(\.text), ["b"])
    }

    // MARK: - The room record

    func testTheRoomListWinsWhileItAgreesWithOverlayText() {
        let list = [Caption(text: "one"), Caption(text: "two")]
        let read = Caption.fromCloud(
            json: Caption.cloudJSON(list), overlayText: "one", sticker: nil)
        XCTAssertEqual(read, list)
    }

    /// 1.5 (31) rewrites `overlayText` and leaves `captionsJSON` behind; the
    /// words just typed win over the stale list.
    func testAStaleRoomListLosesToOverlayText() {
        let list = [Caption(text: "old"), Caption(text: "two")]
        let read = Caption.fromCloud(
            json: Caption.cloudJSON(list), overlayText: "new", sticker: nil)
        XCTAssertEqual(read.map(\.text), ["new"])
    }

    func testARecordWithoutTheNewFieldReadsOverlayText() {
        let sticker = CaptionSticker(x: 0.4, y: 0.4, style: .light)
        let read = Caption.fromCloud(json: nil, overlayText: "only", sticker: sticker)
        XCTAssertEqual(read.map(\.text), ["only"])
        XCTAssertEqual(read.first?.sticker, sticker)
        XCTAssertTrue(Caption.fromCloud(json: nil, overlayText: nil, sticker: nil).isEmpty)
    }

    func testAnUnreadableRoomListReadsOverlayText() {
        let read = Caption.fromCloud(json: "{not json", overlayText: "words", sticker: nil)
        XCTAssertEqual(read.map(\.text), ["words"])
    }

    func testNoCaptionsWritesNoJSON() {
        XCTAssertNil(Caption.cloudJSON([]))
    }

    func testRemoteClipResolvesItsCaptions() {
        let list = [Caption(text: "one"), Caption(text: "two")]
        let clip = CloudKitService.RemoteClip(
            id: "r", day: 1, authorID: "a", authorName: "A", recordedAt: .now,
            localURL: URL(fileURLWithPath: "/tmp/r.mov"), overlayText: "one",
            captionsJSON: Caption.cloudJSON(list))
        XCTAssertEqual(clip.captions.map(\.text), ["one", "two"])
    }

    // MARK: - The store

    @MainActor
    func testUpdateCaptionsKeepsTheListAndDropsBlankOnes() throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        let store = ChallengeStore(
            repository: files, fileStore: files, effects: .isolated)
        let story = store.create(title: "Caption story")

        store.updateCaptions(
            [Caption(text: "top"), Caption(text: "  "), Caption(text: "bottom")],
            day: 1, challengeID: story.id)

        let card = store.challenge(story.id)?.cards.first { $0.day == 1 }
        XCTAssertEqual(card?.captions.map(\.text), ["top", "bottom"])
        XCTAssertEqual(card?.overlayText, "top")
    }

    func testDayClipCarriesEveryCaption() {
        let clip = DayClip(
            day: 1, url: URL(fileURLWithPath: "/tmp/a.mov"),
            captions: [Caption(text: "a"), Caption(text: "b")])
        XCTAssertEqual(clip.overlayText, "a")
        XCTAssertEqual(clip.replacingURL(URL(fileURLWithPath: "/tmp/b.mov")).captions.count, 2)
    }
}
