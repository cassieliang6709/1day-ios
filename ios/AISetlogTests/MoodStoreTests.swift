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

    // MARK: - Mascot chat (removed, 1.5)

    /// 和小方块聊两句 is gone; the chat it saved next to the moods, and the
    /// mascot's name, are cleared the next time the store opens.
    func testTheOldMascotChatIsDeletedOnLaunch() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let chat = tempDir.appendingPathComponent("mascot-chat.json")
        try Data(#"{"2026-10-19":[{"role":"user","content":"secret"}]}"#.utf8).write(to: chat)
        UserDefaults.standard.set("豆豆", forKey: "mascotName")

        _ = makeStore()

        XCTAssertFalse(FileManager.default.fileExists(atPath: chat.path))
        XCTAssertNil(UserDefaults.standard.string(forKey: "mascotName"))
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
