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
    func testPhysicalIPhonePortraitCaptureUsesNinetyDegrees() {
        XCTAssertEqual(
            ClipRecorder.rotationAngle(
                orientation: .portrait,
                devicePosition: .back,
                coordinatedAngle: 0),
            90)
        XCTAssertEqual(
            ClipRecorder.rotationAngle(
                orientation: .portrait,
                devicePosition: .front,
                coordinatedAngle: 270),
            90)
    }

    func testExternalCameraUsesCoordinatorAndLandscapeStaysUnrotated() {
        XCTAssertEqual(
            ClipRecorder.rotationAngle(
                orientation: .portrait,
                devicePosition: .unspecified,
                coordinatedAngle: 270),
            270)
        XCTAssertEqual(
            ClipRecorder.rotationAngle(
                orientation: .landscape,
                devicePosition: .back,
                coordinatedAngle: 90),
            0)
    }

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
