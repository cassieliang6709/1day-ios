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

        XCTAssertEqual(challenge.title, "My day")
        XCTAssertEqual(challenge.cards.count, 3)
        XCTAssertEqual(challenge.resolvedMode, .oneDay)
        XCTAssertEqual(challenge.resolvedClipLength, .tiny)
        XCTAssertEqual(challenge.resolvedOrientation, .portrait)
        XCTAssertEqual(
            challenge.momentTitles,
            ["morning_light", "on_the_move", "golden_hour"])
        XCTAssertEqual(try XCTUnwrap(repository.savedChallenges.first).id, challenge.id)
        XCTAssertEqual(repository.savedChallenges.first?.cards.count, 3)
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
            "0 of 9 2s moments recorded")
        UserDefaults.standard.set(
            AppLanguage.chinese.rawValue,
            forKey: AppLanguage.storageKey)
        XCTAssertEqual(
            Strings.recordedProgress(
                0, total: 9, secondsLabel: "2 秒", unitPlural: "个瞬间"),
            "9 个瞬间中已录 0 段（2 秒）")
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

    func testUpdatingCustomTemplateKeepsItsIdentityAndAllPrompts() throws {
        let repository = MemoryChallengeRepository()
        let store = ChallengeStore(
            repository: repository,
            fileStore: MigrationClipFileStore())
        let template = ChallengeTemplate(
            emoji: "☀️",
            name: LocalizedText(en: "Morning", zh: "Morning"),
            momentKeys: (1...9).map { "Step \($0)" },
            isCustom: true)
        store.addCustomTemplate(template)
        var edited = template
        edited.momentKeys?[8] = "Shower"

        store.updateCustomTemplate(edited)

        XCTAssertEqual(store.customTemplates.first?.id, template.id)
        XCTAssertEqual(store.customTemplates.first?.momentKeys?.count, 9)
        XCTAssertEqual(repository.savedTemplates.first?.momentKeys?.last, "Shower")
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
    /// Portrait takes whatever the rotation coordinator says, for every camera.
    ///
    /// This used to assert a hardcoded 90° for physical cameras. That was the
    /// bug: on an iPhone 17 Pro Max the front camera's pipeline already rotates
    /// its buffers, so forcing another 90° turned every free-form clip a
    /// quarter-turn. The coordinator knows how each camera is mounted; the
    /// function's job is to pass its answer through, not to second-guess it.
    func testPortraitTakesTheCoordinatorsAngleForEveryCamera() {
        for position: AVCaptureDevice.Position in [.back, .front, .unspecified] {
            for angle: CGFloat in [0, 90, 180, 270] {
                XCTAssertEqual(
                    ClipRecorder.rotationAngle(
                        orientation: .portrait,
                        devicePosition: position,
                        coordinatedAngle: angle),
                    angle,
                    "portrait/\(position.rawValue) should pass \(angle) through")
            }
        }
    }

    /// Landscape means the sensor's own frame, so nothing rotates — whatever
    /// the coordinator would have preferred for a horizon-level portrait shot.
    func testLandscapeStaysUnrotatedRegardlessOfCoordinator() {
        for position: AVCaptureDevice.Position in [.back, .front, .unspecified] {
            XCTAssertEqual(
                ClipRecorder.rotationAngle(
                    orientation: .landscape,
                    devicePosition: position,
                    coordinatedAngle: 90),
                0)
        }
    }

}

private final class MemoryChallengeRepository: ChallengeRepository {
    private(set) var savedChallenges: [Challenge] = []
    private(set) var savedTemplates: [ChallengeTemplate] = []

    func loadChallenges() -> [Challenge] { [] }
    func saveChallenges(_ challenges: [Challenge]) { savedChallenges = challenges }
    func loadTemplates() -> [ChallengeTemplate] { [] }
    func saveTemplates(_ templates: [ChallengeTemplate]) { savedTemplates = templates }
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
