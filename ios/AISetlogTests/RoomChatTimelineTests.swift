import XCTest
@testable import AISetlog

/// Clips threaded into the room chat by time (1.5). Built on the phone from
/// the room's clips — nothing new is sent — so the merge is the feature.
final class RoomChatTimelineTests: XCTestCase {
    private let myID = "me"
    private let base = Date(timeIntervalSince1970: 2_000_000)

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    private func message(_ text: String, at minutes: Double, author: String = "ana") -> RoomChatEntry {
        RoomChatEntry(
            message: RoomChatMessage(
                id: UUID(), roomCode: "ABCDEF", authorID: author, authorName: author,
                text: text, createdAt: base.addingTimeInterval(minutes * 60), moment: nil),
            delivery: .sent)
    }

    private func clip(_ author: String, day: Int, at minutes: Double?) -> DayClip {
        DayClip(
            day: day, url: URL(fileURLWithPath: "/tmp/\(author)-\(day).mov"),
            authorName: author == myID ? "Cassie" : author.capitalized, authorID: author,
            recordedAt: minutes.map { base.addingTimeInterval($0 * 60) },
            key: "\(author)-\(day)")
    }

    func testClipsInterleaveWithMessagesByTime() {
        let events = RoomChatTimeline.clipEvents(
            from: [clip("ana", day: 1, at: 5), clip(myID, day: 2, at: 20)],
            myID: myID, momentTitle: { _ in nil })
        let items = RoomChatTimeline.merge(
            entries: [message("hi", at: 0), message("nice", at: 10), message("later", at: 30)],
            clips: events)

        XCTAssertEqual(items.map(\.id).map { $0.hasPrefix("clip") ? "clip" : "msg" },
                       ["msg", "clip", "msg", "clip", "msg"])
    }

    /// A clip and a message from the same instant: the clip first, so the
    /// message reads as being about it.
    func testClipGoesBeforeAMessageAtTheSameInstant() {
        let events = RoomChatTimeline.clipEvents(
            from: [clip("ana", day: 1, at: 10)], myID: myID, momentTitle: { _ in nil })
        let items = RoomChatTimeline.merge(entries: [message("look", at: 10)], clips: events)
        XCTAssertNotNil(items.last?.entry)
    }

    func testMineIsMarkedAndUnstampedClipsAreLeftOut() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        let events = RoomChatTimeline.clipEvents(
            from: [clip(myID, day: 1, at: 1), clip(RoomProgress.soloAuthorID, day: 2, at: 2),
                   clip("ana", day: 3, at: nil)],
            myID: myID, momentTitle: { $0 == 1 ? "午饭" : nil })
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy(\.isMine))
        XCTAssertEqual(events.first?.authorName, "你")
        XCTAssertEqual(events.first?.momentTitle, "午饭")
    }

    func testClipEventLineNamesTheMomentOnlyWhenItHasOne() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.chatClipEvent(name: "小蓝", moment: "午饭"), "小蓝 拍了一段 · 午饭")
        XCTAssertEqual(Strings.chatClipEvent(name: "小蓝", moment: nil), "小蓝 拍了一段")
    }

    /// A shared room's slot has a name or nothing — never 「第 N 天」 — while
    /// a solo story keeps its day wording.
    func testRoomSlotLabelNeverFallsBackToADay() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        let cards = (1...3).map { DayCard(day: $0) }
        let room = Challenge(
            id: UUID(), title: "Room", startDate: base, cards: cards, mode: .sevenDay,
            momentTitles: ["阿福的猫"], roomCode: "ABCDEF")
        let solo = Challenge(
            id: UUID(), title: "Solo", startDate: base, cards: cards, mode: .sevenDay)

        XCTAssertEqual(ChallengePresenter(challenge: room).slotLabel(forSlot: 1), "阿福的猫")
        XCTAssertNil(ChallengePresenter(challenge: room).slotLabel(forSlot: 2))
        XCTAssertEqual(ChallengePresenter(challenge: solo).slotLabel(forSlot: 2), "第 2 天")
    }
}
