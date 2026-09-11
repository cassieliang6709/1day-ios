import XCTest
@testable import AISetlog

/// Exercises the production repository with a disposable defaults domain, not
/// LocalRoomDemoStorage's in-memory challenge array. No live effects/transport.
@MainActor
final class SevenDayPersistentRepositoryTests: XCTestCase {
    func testSevenSavedDaysSurviveFreshRepositoryAndRemainIndependentFromAnotherStory() throws {
        let suite = "1day.seven-day-restart.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let files = try LocalRoomDemoStorage()
        defer { files.close() }
        func makeStore() throws -> ChallengeStore {
            let freshDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let repository = UserDefaultsChallengeRepository(defaults: freshDefaults, fileStore: files)
            let source = LocalRoomSyncSource(code: "LOCAL", clips: [])
            return ChallengeStore(repository: repository, fileStore: files, coverStore: files,
                roomSync: RoomSyncService(fileStore: files, transport: source.transport), effects: .isolated)
        }
        let titles = (1...7).map { "自己写的 Day \($0) 🌱" }
        var store: ChallengeStore? = try makeStore()
        let story = try XCTUnwrap(store).create(title: "My 七日", mode: .sevenDay,
            momentTitles: titles)
        let other = try XCTUnwrap(store).create(title: "Untouched", mode: .oneDay,
            momentTitles: ["Keep this"])
        let input = files.root.appendingPathComponent("generated-fixture.mov")
        let bytes = Data("local test fixture; not a playable-video assertion".utf8)
        try bytes.write(to: input)

        for day in 1...7 {
            try XCTUnwrap(store).saveClip(from: input, day: day, challengeID: story.id,
                overlayText: "本人字幕 \(day) / Caption")
            // Discard the coordinator and repository after each save. The next
            // instance reads the serialized production payload, not its array.
            store = nil
            store = try makeStore()
            let restored = try XCTUnwrap(store?.challenge(story.id))
            XCTAssertEqual(restored.mode, .sevenDay)
            XCTAssertEqual(restored.momentTitles, titles)
            XCTAssertEqual(restored.cards.map(\.day), Array(1...7))
            XCTAssertEqual(restored.recordedCount, day)
            XCTAssertEqual(restored.isComplete, day == 7)
            for savedDay in 1...day {
                let card = restored.cards[savedDay - 1]
                XCTAssertEqual(card.overlayText, "本人字幕 \(savedDay) / Caption")
                XCTAssertEqual(restored.cardStatus(card), .done)
                let url = try XCTUnwrap(store?.clipURL(for: card, in: story.id))
                XCTAssertTrue(url.path.hasPrefix(files.root.path + "/"))
                XCTAssertEqual(try Data(contentsOf: url), bytes)
            }
            XCTAssertEqual(store?.challenge(other.id)?.recordedCount, 0)
            XCTAssertEqual(store?.challenge(other.id)?.momentTitles, ["Keep this"])
        }
        try XCTUnwrap(store).updatePlan(story.id, title: "Edited 标题", momentTitles: titles)
        store = nil
        let final = try makeStore()
        XCTAssertEqual(final.challenge(story.id)?.title, "Edited 标题")
        XCTAssertEqual(final.challenge(story.id)?.recordedCount, 7)
        XCTAssertEqual(try Data(contentsOf: input), bytes)
        let payload = try XCTUnwrap(defaults.data(forKey: UserDefaultsChallengeRepository.defaultsKey))
        let persisted = try JSONDecoder().decode([Challenge].self, from: payload)
        XCTAssertEqual(Set(persisted.map(\.id)), Set([story.id, other.id]))
        XCTAssertTrue(files.loadChallenges().isEmpty, "must not accidentally test the memory repository")
    }
}
