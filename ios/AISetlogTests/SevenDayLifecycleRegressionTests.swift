import XCTest
@testable import AISetlog

@MainActor
final class SevenDayLifecycleRegressionTests: XCTestCase {
    func testSevenDayCalendarStatesSurviveCodableRestartWithoutChangingUserText() throws {
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        let source = LocalRoomSyncSource(code: "LOCAL", clips: [])
        let store = ChallengeStore(repository: files, fileStore: files, coverStore: files,
                                   roomSync: RoomSyncService(fileStore: files, transport: source.transport), effects: .isolated)
        let prompts = (1...7).map { "我的 Day \($0)" }
        let created = store.create(title: "My 七日", mode: .sevenDay, momentTitles: prompts)
        let calendar = Calendar.current
        let noon = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        for elapsed in [0, 1, 6, 7, 30] {
            var story = created
            story.startDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -elapsed, to: noon))
            story.cards[0].clipFileName = "owned-copy.mov"
            story.cards[0].overlayText = "保留 My caption"
            let restarted = try JSONDecoder().decode(Challenge.self, from: JSONEncoder().encode(story))
            XCTAssertEqual(restarted.currentDay, elapsed + 1)
            XCTAssertEqual(restarted.cards.count, 7)
            XCTAssertEqual(restarted.momentTitles, prompts)
            XCTAssertEqual(restarted.title, "My 七日")
            XCTAssertEqual(restarted.cards[0].overlayText, "保留 My caption")
            XCTAssertEqual(restarted.cardStatus(restarted.cards[0]), .done)
            for card in restarted.cards.dropFirst() {
                let expected: DayCard.Status = card.day < elapsed + 1 ? .missed : card.day == elapsed + 1 ? .today : .locked
                XCTAssertEqual(restarted.cardStatus(card), expected)
            }
            XCTAssertEqual(restarted.recordedCount, 1)
            XCTAssertFalse(restarted.isComplete)
        }
    }
}
