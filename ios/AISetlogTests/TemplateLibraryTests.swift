import XCTest
@testable import AISetlog

/// The three things a template library has to get right: it keeps what you
/// built, it gives each one a cover, and an app update doesn't lose the ones
/// you built before covers existed.
final class TemplateLibraryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    // MARK: - Saving into the library

    func testSavedCustomTemplateSurvivesRelaunch() throws {
        let suiteName = "TemplateLibraryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsChallengeRepository(
            defaults: defaults, fileStore: StubClipFileStore())

        let store = ChallengeStore(
            repository: repository,
            fileStore: StubClipFileStore(),
            coverStore: MemoryTemplateCoverStore())
        store.addCustomTemplate(
            ChallengeTemplate(
                name: LocalizedText(en: "Moving day", zh: "搬家日"),
                momentKeys: ["first_box", "the_van", "new_keys"],
                isCustom: true))

        let relaunched = ChallengeStore(
            repository: UserDefaultsChallengeRepository(
                defaults: defaults, fileStore: StubClipFileStore()),
            fileStore: StubClipFileStore(),
            coverStore: MemoryTemplateCoverStore())

        XCTAssertEqual(relaunched.customTemplates.count, 1)
        XCTAssertEqual(relaunched.customTemplates.first?.name.zh, "搬家日")
        XCTAssertEqual(
            relaunched.customTemplates.first?.momentKeys,
            ["first_box", "the_van", "new_keys"])
        XCTAssertTrue(try XCTUnwrap(relaunched.customTemplates.first).isCustom)
    }

    func testAddingTemplateWithCoverFilesThePictureBeforeSaving() throws {
        let covers = MemoryTemplateCoverStore()
        let store = ChallengeStore(
            repository: MemoryRepository(), fileStore: StubClipFileStore(),
            coverStore: covers)

        let saved = store.addCustomTemplate(
            ChallengeTemplate(
                name: LocalizedText(en: "Studio day", zh: "工作室的一天"),
                momentKeys: ["blank_page"], isCustom: true),
            coverImageData: Data([0x01, 0x02]))

        let fileName = try XCTUnwrap(saved.coverFileName)
        XCTAssertEqual(covers.written[fileName], Data([0x01, 0x02]))
        XCTAssertEqual(store.customTemplates.first?.coverFileName, fileName)
        XCTAssertEqual(store.coverURL(for: saved)?.lastPathComponent, fileName)
    }

    func testReplacingACoverDeletesTheOneItReplaced() throws {
        let covers = MemoryTemplateCoverStore()
        let store = ChallengeStore(
            repository: MemoryRepository(), fileStore: StubClipFileStore(),
            coverStore: covers)
        let saved = store.addCustomTemplate(
            ChallengeTemplate(
                name: LocalizedText(en: "Studio day", zh: "工作室的一天"),
                momentKeys: ["blank_page"], isCustom: true),
            coverImageData: Data([0x01]))
        let first = try XCTUnwrap(saved.coverFileName)

        store.updateCustomTemplate(saved, coverImageData: Data([0x02]))

        let second = try XCTUnwrap(store.customTemplates.first?.coverFileName)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(covers.deleted, [first])
        XCTAssertNil(covers.written[first])
    }

    func testClearingACoverGoesBackToMatchedArtAndDeletesTheFile() throws {
        let covers = MemoryTemplateCoverStore()
        let store = ChallengeStore(
            repository: MemoryRepository(), fileStore: StubClipFileStore(),
            coverStore: covers)
        var saved = store.addCustomTemplate(
            ChallengeTemplate(
                name: LocalizedText(en: "Studio day", zh: "工作室的一天"),
                momentKeys: ["blank_page"], isCustom: true),
            coverImageData: Data([0x01]))
        let fileName = try XCTUnwrap(saved.coverFileName)

        saved.coverFileName = nil
        store.updateCustomTemplate(saved)

        XCTAssertNil(store.customTemplates.first?.coverFileName)
        XCTAssertEqual(covers.deleted, [fileName])
        XCTAssertNil(store.coverURL(for: try XCTUnwrap(store.customTemplates.first)))
    }

    func testDeletingATemplateTakesItsCoverWithIt() throws {
        let covers = MemoryTemplateCoverStore()
        let store = ChallengeStore(
            repository: MemoryRepository(), fileStore: StubClipFileStore(),
            coverStore: covers)
        let saved = store.addCustomTemplate(
            ChallengeTemplate(
                name: LocalizedText(en: "Studio day", zh: "工作室的一天"),
                momentKeys: ["blank_page"], isCustom: true),
            coverImageData: Data([0x01]))

        store.deleteCustomTemplate(saved)

        XCTAssertTrue(store.customTemplates.isEmpty)
        XCTAssertEqual(covers.deleted, [try XCTUnwrap(saved.coverFileName)])
    }

    func testAFailedCoverWriteLeavesTheTemplateWithoutOneRatherThanLosingIt() {
        let covers = MemoryTemplateCoverStore()
        covers.failsWrites = true
        let store = ChallengeStore(
            repository: MemoryRepository(), fileStore: StubClipFileStore(),
            coverStore: covers)

        let saved = store.addCustomTemplate(
            ChallengeTemplate(
                name: LocalizedText(en: "Studio day", zh: "工作室的一天"),
                momentKeys: ["blank_page"], isCustom: true),
            coverImageData: Data([0x01]))

        XCTAssertNil(saved.coverFileName)
        XCTAssertEqual(store.customTemplates.count, 1)
    }

    // MARK: - Matching a cover to the moments

    func testMomentsSharedWithABuiltInBorrowItsPoster() {
        XCTAssertEqual(
            TemplateCoverMatcher.assetName(
                forMomentKeys: ["ingredients", "the_sizzle", "first_bite"]),
            "TemplateCookWithMe")
        XCTAssertEqual(
            TemplateCoverMatcher.assetName(
                forMomentKeys: ["desk_setup", "first_sprint", "shut_the_laptop"]),
            "TemplateLockIn")
    }

    /// Legacy custom templates stored English display strings, not keys.
    func testLegacyDisplayStringsStillMatchAPoster() {
        XCTAssertEqual(
            TemplateCoverMatcher.assetName(
                forMomentKeys: ["Ingredients", "The sizzle", "First bite"]),
            "TemplateCookWithMe")
    }

    func testTheMostOverlappingBuiltInWins() {
        // "the_wall" and "little_win" belong to Lock In and Study Streak both;
        // the extra Lock In moment has to break the tie.
        XCTAssertEqual(
            TemplateCoverMatcher.assetName(
                forMomentKeys: ["the_wall", "little_win", "breakthrough", "refuel"]),
            "TemplateLockIn")
    }

    func testHandTypedPromptsAreMatchedByTheirWords() {
        XCTAssertEqual(
            TemplateCoverMatcher.assetName(
                forMomentKeys: ["先把菜洗了", "下厨", "端上桌"], name: "做饭的一天"),
            "TemplateCookWithMe")
        XCTAssertEqual(
            TemplateCoverMatcher.assetName(
                forMomentKeys: ["Warm up", "The gym", "Cool down"], name: "Leg day"),
            "TemplateSevenDaysMoving")
    }

    func testMatchingIsStableForTheSameMoments() {
        let moments = ["把桌子收一收", "泡杯茶", "看会儿书"]
        let first = TemplateCoverMatcher.assetName(forMomentKeys: moments)
        let second = TemplateCoverMatcher.assetName(forMomentKeys: moments)
        XCTAssertEqual(first, second)
    }

    func testPromptsThatSayNothingRecognisableGetNoMatch() {
        XCTAssertNil(
            TemplateCoverMatcher.assetName(forMomentKeys: ["zzz", "qqq"], name: "xyz"))
        XCTAssertNil(TemplateCoverMatcher.assetName(forMomentKeys: []))
    }

    func testCustomTemplateFallsBackToTheSharedArtWhenNothingMatches() {
        let template = ChallengeTemplate(
            name: LocalizedText(en: "xyz", zh: "xyz"),
            momentKeys: ["zzz"], isCustom: true)

        XCTAssertEqual(template.matchedCoverAssetName, "TemplateCustomStory")
    }

    func testBuiltInsKeepTheirOwnPainting() {
        for template in ChallengeTemplate.allBuiltins {
            XCTAssertEqual(template.matchedCoverAssetName, template.coverAssetName)
        }
    }

    func testACustomStoryTakesTheCoverItsPromptsEarn() {
        let challenge = Challenge(
            id: UUID(), title: "Moving day", startDate: .now,
            cards: [DayCard(day: 1)],
            momentTitles: ["ingredients", "plate_it"])

        XCTAssertEqual(
            ChallengePresenter(challenge: challenge).coverAssetName,
            "TemplateCookWithMe")
    }

    // MARK: - Migration

    func testTemplatesBuiltBeforeCoversMigrateWithoutLoss() throws {
        let suiteName = "TemplateLibraryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Exactly what v1 wrote: no coverFileName key at all, and moments as
        // English display strings from the era before catalog keys.
        let legacy = """
        [{"id":"\(UUID().uuidString)","emoji":"🎬","isCustom":true,
          "name":"Perfect Morning","momentTitles":["Wake up","Coffee"]}]
        """
        defaults.set(Data(legacy.utf8), forKey: UserDefaultsChallengeRepository.legacyTemplatesKey)

        let repository = UserDefaultsChallengeRepository(
            defaults: defaults, fileStore: StubClipFileStore())
        let migrated = repository.loadTemplates()

        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.name.en, "Perfect Morning")
        XCTAssertEqual(migrated.first?.momentKeys, ["wake_up", "coffee"])
        XCTAssertNil(migrated.first?.coverFileName)
        // Re-filed under the new key, and the old one is gone.
        XCTAssertNotNil(defaults.data(forKey: UserDefaultsChallengeRepository.templatesKey))
        XCTAssertNil(defaults.data(forKey: UserDefaultsChallengeRepository.legacyTemplatesKey))
        // And still there on the next launch, without the legacy key to lean on.
        XCTAssertEqual(
            UserDefaultsChallengeRepository(defaults: defaults, fileStore: StubClipFileStore())
                .loadTemplates().first?.name.en,
            "Perfect Morning")
    }

    func testAnUploadedCoverSurvivesEncodingAndDecoding() throws {
        let template = ChallengeTemplate(
            name: LocalizedText(en: "Studio day", zh: "工作室的一天"),
            momentKeys: ["blank_page"], isCustom: true,
            coverFileName: "abc.coverimg")

        let data = try JSONEncoder().encode([template])
        let decoded = try JSONDecoder().decode([ChallengeTemplate].self, from: data)

        XCTAssertEqual(decoded.first?.coverFileName, "abc.coverimg")
    }
}

// MARK: - Doubles

private final class MemoryTemplateCoverStore: TemplateCoverStore {
    private(set) var written: [String: Data] = [:]
    private(set) var deleted: [String] = []
    var failsWrites = false

    func storeCover(_ imageData: Data, templateID: UUID) -> String? {
        guard !failsWrites else { return nil }
        let fileName = "\(templateID.uuidString)-\(written.count).coverimg"
        written[fileName] = imageData
        return fileName
    }

    func coverURL(fileName: String) -> URL? {
        guard written[fileName] != nil else { return nil }
        return URL(fileURLWithPath: "/tmp/templateCovers").appendingPathComponent(fileName)
    }

    func deleteCover(fileName: String) {
        deleted.append(fileName)
        written[fileName] = nil
    }
}

private final class MemoryRepository: ChallengeRepository {
    private(set) var savedTemplates: [ChallengeTemplate] = []

    func loadChallenges() -> [Challenge] { [] }
    func saveChallenges(_ challenges: [Challenge]) {}
    func loadTemplates() -> [ChallengeTemplate] { [] }
    func saveTemplates(_ templates: [ChallengeTemplate]) { savedTemplates = templates }
}

private final class StubClipFileStore: ClipFileStore {
    func storeClip(from tempURL: URL, day: Int, challengeID: UUID) -> String? { nil }

    func clipURL(fileName: String, challengeID: UUID) -> URL {
        URL(fileURLWithPath: "/tmp").appendingPathComponent(fileName)
    }

    func deleteClips(challengeID: UUID) {}

    func remoteCacheDir(roomCode: String) -> URL {
        URL(fileURLWithPath: "/tmp").appendingPathComponent(roomCode)
    }

    func deleteRemoteCache(roomCode: String) {}
    func migrateLegacyClips(_ fileNames: [String], into challengeID: UUID) {}
}
