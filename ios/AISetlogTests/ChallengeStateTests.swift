import XCTest
import AVFoundation
@testable import AISetlog

final class ChallengeStateTests: XCTestCase {
    /// Some assertions cover localized fallback strings — pin the app language
    /// so the result doesn't depend on the test device's locale.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    func testDayCardStatesCoverDoneTodayMissedAndLocked() {
        XCTAssertEqual(DayCard(day: 1, clipFileName: "day1.mov").status(currentDay: 2), .done)
        XCTAssertEqual(DayCard(day: 2).status(currentDay: 2), .today)
        XCTAssertEqual(DayCard(day: 1).status(currentDay: 2), .missed)
        XCTAssertEqual(DayCard(day: 3).status(currentDay: 2), .locked)
    }

    func testChallengeCompletionTracksRecordedCards() {
        let challenge = Challenge(
            id: UUID(),
            title: "Morning routine",
            startDate: .now,
            cards: [
                DayCard(day: 1, clipFileName: "day1.mov"),
                DayCard(day: 2, clipFileName: "day2.mov"),
            ]
        )

        XCTAssertEqual(challenge.recordedCount, 2)
        XCTAssertTrue(challenge.isComplete)
    }

    func testOneDayChallengeTreatsOpenMomentsAsToday() {
        let challenge = Challenge(
            id: UUID(),
            title: "Soft reset",
            startDate: .now,
            cards: [DayCard(day: 1), DayCard(day: 2)],
            mode: .oneDay
        )

        XCTAssertEqual(challenge.cardStatus(challenge.cards[0]), .today)
        XCTAssertEqual(challenge.cardStatus(challenge.cards[1]), .today)
    }

    func testCustomMomentTitlesDriveLabels() {
        let challenge = Challenge(
            id: UUID(),
            title: "Deep focus",
            startDate: .now,
            cards: [DayCard(day: 1), DayCard(day: 2)],
            momentTitles: ["Setup", "Solved bit"]
        )
        let presenter = ChallengePresenter(challenge: challenge)

        XCTAssertEqual(challenge.momentValue(forSlot: 1), "Setup")
        XCTAssertNil(challenge.momentValue(forSlot: 3))
        XCTAssertEqual(presenter.title(forSlot: 1), "Setup")
        XCTAssertEqual(presenter.title(forSlot: 2), "Solved bit")
        XCTAssertEqual(presenter.title(forSlot: 3), "Day 3")
    }

    func testQuickStartCreatesAndPersistsThreeMomentPersonalFilm() throws {
        let repository = MemoryChallengeRepository()
        let store = ChallengeStore(
            repository: repository,
            fileStore: MigrationClipFileStore())

        let challenge = store.createQuickStart()

        // 1.5: the first story is 按时间 — no prompts, seven open slots.
        XCTAssertEqual(challenge.title, "My day")
        XCTAssertEqual(challenge.cards.count, 7)
        XCTAssertEqual(challenge.resolvedMode, .oneDay)
        XCTAssertEqual(challenge.resolvedClipLength, .tiny)
        XCTAssertEqual(challenge.resolvedOrientation, .portrait)
        XCTAssertTrue(challenge.isTimeOnly)
        XCTAssertNil(challenge.momentTitles)
        XCTAssertEqual(try XCTUnwrap(repository.savedChallenges.first).id, challenge.id)
        XCTAssertEqual(repository.savedChallenges.first?.cards.count, 7)
    }

    func testPresenterUnitNamesFollowMode() {
        func make(mode: Challenge.Mode) -> Challenge {
            Challenge(
                id: UUID(), title: "t", startDate: .now,
                cards: [DayCard(day: 1)], mode: mode)
        }

        XCTAssertEqual(ChallengePresenter(challenge: make(mode: .oneDay)).unitName, Strings.unitName(oneDay: true))
        XCTAssertEqual(ChallengePresenter(challenge: make(mode: .sevenDay)).unitNamePlural, Strings.unitNamePlural(oneDay: false))
        XCTAssertEqual(ChallengePresenter(challenge: make(mode: .oneDay)).storyLabel, Strings.storyLabel(oneDay: true))
    }
    func testCustomTemplateOverSevenPromptsCreatesEveryCaptureSlot() throws {
        let repository = MemoryChallengeRepository()
        let store = ChallengeStore(
            repository: repository,
            fileStore: MigrationClipFileStore())
        let prompts = (1...9).map { "Moment \($0)" }

        let challenge = store.create(
            title: "Long morning",
            mode: .oneDay,
            momentTitles: prompts)

        XCTAssertEqual(challenge.cards.count, 9)
        XCTAssertEqual(challenge.momentTitles, prompts)
        XCTAssertEqual(
            ChallengePresenter(challenge: challenge).title(forSlot: 9),
            "Moment 9")
        XCTAssertEqual(repository.savedChallenges.first?.cards.count, 9)
        XCTAssertEqual(
            Strings.recordedProgress(
                0, total: 9, secondsLabel: "2s", unitPlural: "moments"),
            "0 of 9 moments recorded · up to 2s each")
        UserDefaults.standard.set(
            AppLanguage.chinese.rawValue,
            forKey: AppLanguage.storageKey)
        XCTAssertEqual(
            Strings.recordedProgress(
                0, total: 9, secondsLabel: "2 秒", unitPlural: "个瞬间"),
            "9 个瞬间中已录 0 段（每段最长 2 秒）")
    }

    func testUpdatingPlanTitlesPersistsWithoutDroppingSlotsOrClips() throws {
        let repository = MemoryChallengeRepository()
        let store = ChallengeStore(
            repository: repository,
            fileStore: MigrationClipFileStore())
        let original = store.create(
            title: "Morning routine",
            mode: .oneDay,
            momentTitles: ["Wake", "Coffee", "After"])
        store.challenges[0].cards[0].clipFileName = "day1.mov"

        store.updatePlan(
            original.id,
            title: "Perfect morning",
            momentTitles: ["Wake", "Coffee", "Shower"])

        let updated = try XCTUnwrap(store.challenge(original.id))
        XCTAssertEqual(updated.title, "Perfect morning")
        XCTAssertEqual(updated.cards.count, 3)
        XCTAssertEqual(updated.momentTitles, ["Wake", "Coffee", "Shower"])
        XCTAssertEqual(updated.cards[0].clipFileName, "day1.mov")
        XCTAssertEqual(repository.savedChallenges.first?.momentTitles?.last, "Shower")
    }

    /// 编辑计划 rewrites the list: footage follows its item when reordered,
    /// a new item gets an empty slot, and slots are renumbered 1…n.
    func testReplacingPlanMovesFootageWithItsItem() throws {
        let store = ChallengeStore(
            repository: MemoryChallengeRepository(),
            fileStore: MigrationClipFileStore())
        let plan = store.create(title: "Day", mode: .oneDay, momentTitles: ["A", "B", "C"])
        store.challenges[0].cards[2].clipFileName = "c.mov"

        // C moved to the top, B dropped, a new D at the end.
        store.replacePlan(plan.id, items: [
            (title: "C", fromSlot: 3), (title: "A", fromSlot: 1), (title: "D", fromSlot: nil),
        ])

        let updated = try XCTUnwrap(store.challenge(plan.id))
        XCTAssertEqual(updated.momentTitles, ["C", "A", "D"])
        XCTAssertEqual(updated.cards.map(\.day), [1, 2, 3])
        XCTAssertEqual(updated.cards[0].clipFileName, "c.mov")
        XCTAssertNil(updated.cards[1].clipFileName)
        XCTAssertNil(updated.cards[2].clipFileName)
    }

    /// 从提醒事项导入 lists what's due by today first, then undated, then later.
    func testRemindersDueTodayComeFirst() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = calendar.date(byAdding: .day, value: 3, to: now)!
        let overdue = calendar.date(byAdding: .day, value: -1, to: now)!
        let items = [
            RemindersImport.Item(id: "1", title: "Later", due: later),
            RemindersImport.Item(id: "2", title: "Undated", due: nil),
            RemindersImport.Item(id: "3", title: "Today", due: now),
            RemindersImport.Item(id: "4", title: "Overdue", due: overdue),
        ]
        XCTAssertEqual(
            RemindersImport.ordered(items, now: now, calendar: calendar).map(\.title),
            ["Overdue", "Today", "Undated", "Later"])
    }

    func testLegacyChallengeMigrationSurvivesRelaunch() throws {
        struct LegacyChallenge: Codable {
            var title: String
            var startDate: Date
            var cards: [DayCard]
        }

        let suiteName = "ChallengeStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = LegacyChallenge(
            title: "Migrated week",
            startDate: .now,
            cards: [DayCard(day: 1, clipFileName: "day1.mov")])
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: "challenge.v1")

        let fileStore = MigrationClipFileStore()
        let repository = UserDefaultsChallengeRepository(
            defaults: defaults,
            fileStore: fileStore)

        let firstLaunch = repository.loadChallenges()
        let secondLaunch = repository.loadChallenges()

        XCTAssertEqual(firstLaunch.count, 1)
        XCTAssertEqual(secondLaunch.map(\.id), firstLaunch.map(\.id))
        XCTAssertEqual(fileStore.migratedFileNames, ["day1.mov"])
    }
    /// 竖拍 and 横拍 each have one angle per camera; only the switch and the
    /// camera's sensor decide it, never how the phone is held.
    func testAnglesFollowTheSwitchAndTheSensor() {
        // Back cameras: landscape sensor (1920×1080).
        XCTAssertEqual(CameraOrientation.captureAngle(sideways: false, nativePortrait: false, front: false), 90)
        XCTAssertEqual(CameraOrientation.captureAngle(sideways: true, nativePortrait: false, front: false), 0)
        XCTAssertEqual(CameraOrientation.previewAngle(nativePortrait: false), 90)
        // iPhone 17 front camera: portrait sensor (1080×1920). It faces the
        // other way, so 横拍 turns it the other way: 90°, not 270°, which
        // filmed it upside down.
        XCTAssertEqual(CameraOrientation.captureAngle(sideways: false, nativePortrait: true, front: true), 0)
        XCTAssertEqual(CameraOrientation.captureAngle(sideways: true, nativePortrait: true, front: true), 90)
        XCTAssertEqual(CameraOrientation.previewAngle(nativePortrait: true), 0)
        // Older front cameras: landscape sensor, 横拍 at 180°.
        XCTAssertEqual(CameraOrientation.captureAngle(sideways: false, nativePortrait: false, front: true), 90)
        XCTAssertEqual(CameraOrientation.captureAngle(sideways: true, nativePortrait: false, front: true), 180)
    }

    /// Measured on an iPhone 17 Pro Max: the front camera at 90° wrote a
    /// 1080×1920 frame turned a quarter (shown landscape) in 竖拍. Turned
    /// back it is the mirrored upright frame the same camera wrote at 0°.
    func testASidewaysSelfieIsTurnedUpright() {
        let fixed = CameraOrientation.corrected(
            natural: CGSize(width: 1080, height: 1920),
            transform: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0),
            landscape: false)
        XCTAssertEqual(fixed, CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1080, ty: 0))
    }

    /// A front camera not yet known to be portrait gets 180° in 横拍 and comes
    /// out upright; turned, it is landscape, still mirrored, and the same as
    /// the 90° the table now gives it.
    func testAFirstSelfieInLandscapeIsTurnedTheRightWay() {
        let natural = CGSize(width: 1080, height: 1920)
        let at180 = CGAffineTransform(rotationAngle: .pi).concatenating(
            CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
        let fixed = CameraOrientation.corrected(
            natural: natural,
            transform: CGAffineTransform(
                a: at180.a.rounded(), b: at180.b.rounded(), c: at180.c.rounded(), d: at180.d.rounded(),
                tx: 0, ty: 1920),
            landscape: true)
        // 90° plus the selfie mirror, as the measured 90° take had it.
        XCTAssertEqual(fixed, CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0))
        let shown = CGRect(origin: .zero, size: natural).applying(fixed!)
        XCTAssertEqual(shown, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    /// A take already the right shape is left alone — the back camera's,
    /// as measured.
    func testATakeOfTheRightShapeIsLeftAlone() {
        XCTAssertNil(CameraOrientation.corrected(
            natural: CGSize(width: 1920, height: 1080),
            transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0),
            landscape: false))
        XCTAssertNil(CameraOrientation.corrected(
            natural: CGSize(width: 1920, height: 1080), transform: .identity, landscape: true))
    }

    /// A camera is landscape until a take shows otherwise, and only a real
    /// change asks for the angles to be set again.
    func testASensorsShapeIsRememberedPerCamera() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CameraOrientationTests"))
        defaults.removePersistentDomain(forName: "CameraOrientationTests")
        XCTAssertFalse(CameraOrientation.nativePortrait(uniqueID: "front", defaults: defaults))
        XCTAssertTrue(CameraOrientation.remember(nativePortrait: true, for: "front", defaults: defaults))
        XCTAssertFalse(CameraOrientation.remember(nativePortrait: true, for: "front", defaults: defaults))
        XCTAssertFalse(CameraOrientation.remember(nativePortrait: false, for: "back", defaults: defaults))
        XCTAssertTrue(CameraOrientation.nativePortrait(uniqueID: "front", defaults: defaults))
        XCTAssertFalse(CameraOrientation.nativePortrait(uniqueID: "back", defaults: defaults))
        defaults.removePersistentDomain(forName: "CameraOrientationTests")
    }

    /// Only square is cropped after recording. The other two are whatever the
    /// camera wrote, and a copy pass over them would be an export for nothing.
    func testOnlySquareCropsAfterRecording() {
        XCTAssertTrue(Challenge.Orientation.square.cropsAfterRecording)
        XCTAssertFalse(Challenge.Orientation.portrait.cropsAfterRecording)
        XCTAssertFalse(Challenge.Orientation.landscape.cropsAfterRecording)
    }

}

private final class MemoryChallengeRepository: ChallengeRepository {
    private(set) var savedChallenges: [Challenge] = []

    func loadChallenges() -> [Challenge] { [] }
    func saveChallenges(_ challenges: [Challenge]) { savedChallenges = challenges }
}

private final class MigrationClipFileStore: ClipFileStore {
    private(set) var migratedFileNames: [String] = []

    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? { nil }

    func clipURL(fileName: String, challengeID: UUID) -> URL {
        URL(fileURLWithPath: "/tmp").appendingPathComponent(fileName)
    }

    func deleteClips(challengeID: UUID) {}

    func remoteCacheDir(roomCode: String) -> URL {
        URL(fileURLWithPath: "/tmp").appendingPathComponent(roomCode)
    }

    func deleteRemoteCache(roomCode: String) {}

    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {
        migratedFileNames = fileNames
    }
}
