import XCTest
import CloudKit
@testable import AISetlog

/// 心情日记: one entry per day, changeable all day, survives a relaunch, and
/// maps to the `MoodEntry` CloudKit record without loss. No test here touches
/// CloudKit — the store is built with `sync: nil` or a fake.
@MainActor
final class MoodStoreTests: XCTestCase {
    private var tempDir: URL!
    private var clock = Date(timeIntervalSince1970: 1_760_600_000) // 2025-10-16, mid-day UTC

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private var fileURL: URL { tempDir.appendingPathComponent("moods.json") }

    private func makeStore(sync: MoodSyncing? = nil) -> MoodStore {
        MoodStore(fileURL: fileURL, sync: sync, now: { [unowned self] in self.clock })
    }

    // MARK: - Setting and replacing

    func testSettingTodaysMoodCreatesOneEntry() {
        let store = makeStore()
        XCTAssertNil(store.today)

        store.setMood(.happy)

        XCTAssertEqual(store.today?.mood, .happy)
        XCTAssertEqual(store.today?.day, MoodDay.key(for: clock))
        XCTAssertEqual(store.entries.count, 1)
    }

    func testChangingTheMoodLaterTheSameDayReplacesItAndKeepsTheNote() {
        let store = makeStore()
        store.setMood(.tired)
        store.setNote("slept badly")
        clock += 3600

        store.setMood(.calm)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.today?.mood, .calm)
        XCTAssertEqual(store.today?.note, "slept badly")
        XCTAssertEqual(store.today?.updatedAt, clock)
    }

    func testANoteWithoutAMoodIsIgnored() {
        let store = makeStore()
        store.setNote("hello")
        XCTAssertNil(store.today)
    }

    func testTheNextDayIsASeparateEntry() {
        let store = makeStore()
        store.setMood(.sad)
        let yesterday = clock
        clock += 86_400

        XCTAssertNil(store.today)
        store.setMood(.angry)

        XCTAssertEqual(store.mood(on: yesterday)?.mood, .sad)
        XCTAssertEqual(store.mood(on: clock)?.mood, .angry)
        XCTAssertEqual(store.entries.count, 2)
    }

    // MARK: - Persistence

    func testEntriesSurviveARelaunch() {
        let first = makeStore()
        first.setMood(.happy)
        first.setNote("good day")
        let saved = first.today

        let second = makeStore()

        XCTAssertEqual(second.today, saved)
    }

    // MARK: - Merge (last write wins)

    func testNewerRemoteEntryReplacesLocalOlderDoesNot() {
        let store = makeStore()
        store.setMood(.calm)
        let day = MoodDay.key(for: clock)

        store.merge([MoodEntry(day: day, mood: .sad, note: "old", updatedAt: clock - 60)])
        XCTAssertEqual(store.today?.mood, .calm)

        store.merge([MoodEntry(day: day, mood: .angry, note: "new", updatedAt: clock + 60)])
        XCTAssertEqual(store.today?.mood, .angry)
        XCTAssertEqual(store.today?.note, "new")
    }

    func testPendingEditsArePushedOnSync() async {
        let fake = FakeSync()
        let store = makeStore(sync: fake)
        store.setMood(.tired)

        await store.syncNow()

        XCTAssertEqual(fake.pushed.last?.mood, .tired)
    }

    // MARK: - Record mapping

    func testRecordRoundTrip() throws {
        let entry = MoodEntry(day: "2026-10-16", mood: .calm, note: "tea", updatedAt: clock)
        let record = MoodSync.record(for: entry)

        XCTAssertEqual(record.recordType, "MoodEntry")
        XCTAssertEqual(record.recordID.recordName, "mood-2026-10-16")
        XCTAssertEqual(record["day"] as? String, "2026-10-16")
        XCTAssertEqual(record["mood"] as? String, "calm")
        XCTAssertEqual(record["note"] as? String, "tea")
        XCTAssertEqual(record["updatedAt"] as? Date, clock)
        XCTAssertEqual(MoodSync.entry(from: record), entry)
    }

    func testRecordWithUnknownMoodIsSkipped() {
        let record = MoodSync.record(for: MoodEntry(day: "2026-10-16", mood: .happy, note: "", updatedAt: clock))
        record["mood"] = "ecstatic" as CKRecordValue
        XCTAssertNil(MoodSync.entry(from: record))
    }

    // MARK: - Saved state

    func testCardIsEditorUntilAMoodExistsThenSaved() {
        let store = makeStore()
        XCTAssertEqual(MoodCardPhase(entry: store.today, isEditing: false), .editing)
        store.setMood(.happy)
        XCTAssertEqual(MoodCardPhase(entry: store.today, isEditing: true), .editing)
        XCTAssertEqual(MoodCardPhase(entry: store.today, isEditing: false), .saved)
    }

    func testASavedDayIsStillSavedAfterARelaunch() {
        let first = makeStore()
        first.setMood(.calm)
        first.setNote("tea")

        let second = makeStore()

        XCTAssertEqual(MoodCardPhase(entry: second.today, isEditing: false), .saved)
        XCTAssertEqual(second.today?.note, "tea")
    }

    // MARK: - Mascot chat

    func testChatNeedsAMoodFirst() {
        let store = makeStore()
        XCTAssertFalse(store.appendChat(.user, "hi"))
        XCTAssertTrue(store.chat().isEmpty)
    }

    func testChatIsPerDayAndSurvivesARelaunch() {
        let first = makeStore()
        first.setMood(.tired)
        first.appendChat(.assistant, "辛苦啦")
        first.appendChat(.user, "  好累  ")
        let yesterday = clock
        clock += 86_400

        let second = makeStore()

        XCTAssertTrue(second.chat().isEmpty)
        XCTAssertEqual(second.chat(on: yesterday).map(\.content), ["辛苦啦", "好累"])
        XCTAssertEqual(second.chat(on: yesterday).map(\.role), [.assistant, .user])
    }

    func testChatStopsAtTheLimitAndLeavesRoomForTheLastReply() {
        let store = makeStore()
        store.setMood(.happy)
        for i in 0..<(MoodStore.chatLimit - 2) {
            store.appendChat(i.isMultiple(of: 2) ? .user : .assistant, "line \(i)")
        }
        XCTAssertTrue(store.canSendChat())
        store.appendChat(.user, "last")
        XCTAssertFalse(store.canSendChat())
        XCTAssertTrue(store.appendChat(.assistant, "bye"))
        XCTAssertFalse(store.appendChat(.user, "one more"))
        XCTAssertEqual(store.chat().count, MoodStore.chatLimit)
    }

    func testChatIsNeverInTheSyncedSnapshot() async throws {
        let fake = FakeSync()
        let store = makeStore(sync: fake)
        store.setMood(.sad)
        store.appendChat(.user, "secret")
        await store.syncNow()

        let synced = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(synced.contains("secret"))
        XCTAssertFalse(fake.pushed.contains { $0.note.contains("secret") })
    }

    func testMascotChatRequestAndReplyParsing() throws {
        let history = [MascotChatMessage(role: .user, content: "hi")]
        let data = try XCTUnwrap(RemoteMascotChatService.requestBody(
            mood: .tired, note: "late", history: history, language: .english, device: "d"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["mood"] as? String, "tired")
        XCTAssertEqual(json["note"] as? String, "late")
        XCTAssertEqual(json["language"] as? String, "en")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": "hi"]])

        XCTAssertEqual(try RemoteMascotChatService.reply(from: Data(#"{"reply":" 嗨 "}"#.utf8)), "嗨")
        XCTAssertThrowsError(try RemoteMascotChatService.reply(from: Data(#"{"reply":""}"#.utf8)))
        XCTAssertThrowsError(try RemoteMascotChatService.reply(from: Data("nope".utf8)))
    }

    func testEveryMoodHasAnImageInTheAppBundle() {
        for mood in Mood.allCases {
            XCTAssertNotNil(UIImage(named: mood.imageName, in: Bundle(for: MoodStore.self), with: nil), mood.imageName)
        }
    }
}

private final class FakeSync: MoodSyncing {
    var pushed: [MoodEntry] = []
    func push(_ entries: [MoodEntry]) async throws { pushed.append(contentsOf: entries) }
    func fetchChanges() async throws -> [MoodEntry] { [] }
    func isAvailable() async -> Bool { true }
}
