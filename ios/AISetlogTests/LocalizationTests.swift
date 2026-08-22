import XCTest
@testable import AISetlog

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    // MARK: AppLanguage.resolved

    func testSystemLanguageFollowsLocale() {
        let zh = Locale(identifier: "zh-Hans")
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(AppLanguage.system.resolved(locale: zh), .chinese)
        XCTAssertEqual(AppLanguage.system.resolved(locale: en), .english)
        XCTAssertEqual(AppLanguage.english.resolved(locale: zh), .english)
        XCTAssertEqual(AppLanguage.chinese.resolved(locale: en), .chinese)
    }

    func testEffectiveReadsUserDefaults() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(AppLanguage.effective, .chinese)
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(AppLanguage.effective, .english)
    }

    // MARK: LocalizedText

    func testLocalizedTextResolvesPerLanguage() {
        let text = LocalizedText(en: "Wake up", zh: "起床")
        XCTAssertEqual(text.resolved(.english), "Wake up")
        XCTAssertEqual(text.resolved(.chinese), "起床")
    }

    func testLocalizedTextFallsBackToEnglish() {
        let text = LocalizedText(translations: ["en": "Only English"])
        XCTAssertEqual(text.resolved(.chinese), "Only English")
    }

    func testLocalizedTextDecodesLegacyEnZhFormat() throws {
        let legacy = #"{"en":"Wake up","zh":"起床"}"#.data(using: .utf8)!
        let text = try JSONDecoder().decode(LocalizedText.self, from: legacy)
        XCTAssertEqual(text.resolved(.english), "Wake up")
        XCTAssertEqual(text.resolved(.chinese), "起床")
        XCTAssertEqual(text.en, "Wake up")
        XCTAssertEqual(text.zh, "起床")
    }

    func testLocalizedTextRoundTripsNewFormat() throws {
        let original = LocalizedText(en: "Wake up", zh: "起床")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocalizedText.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: Template identity and story titles

    func testBuiltInTemplateLookupAcceptsStableAndLegacyLocalizedNames() {
        XCTAssertEqual(
            ChallengeTemplate.builtIn(matching: "Soft Reset")?.coverAssetName,
            "TemplateSoftReset")
        XCTAssertEqual(
            ChallengeTemplate.builtIn(matching: "慢慢重启")?.identityKey,
            "Soft Reset")
        XCTAssertNil(ChallengeTemplate.builtIn(matching: "My own story"))
    }

    func testBuiltInDefaultTitleSwitchesIndependentlyBetweenLanguages() {
        let challenge = Challenge(
            id: UUID(),
            title: "Soft Reset",
            startDate: .now,
            cards: [DayCard(day: 1)],
            mode: .oneDay,
            templateName: "Soft Reset")
        let presenter = ChallengePresenter(challenge: challenge)

        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(presenter.displayTitle, "慢慢重启")
        XCTAssertEqual(presenter.coverAssetName, "TemplateSoftReset")

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(presenter.displayTitle, "Soft Reset")
    }

    func testUserEditedTitleIsNotTranslatedAndCustomStoryGetsArtwork() {
        let challenge = Challenge(
            id: UUID(),
            title: "Cassie's Sunday",
            startDate: .now,
            cards: [DayCard(day: 1)],
            mode: .oneDay,
            templateName: "Soft Reset")
        let presenter = ChallengePresenter(challenge: challenge)

        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(presenter.displayTitle, "Cassie's Sunday")

        let custom = Challenge(
            id: UUID(),
            title: "我的周末",
            startDate: .now,
            cards: [DayCard(day: 1)],
            mode: .oneDay,
            templateName: "我的周末")
        XCTAssertEqual(
            ChallengePresenter(challenge: custom).coverAssetName,
            "TemplateCustomStory")
    }

    // MARK: Strings

    func testStringsSwitchWithStoredLanguage() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.startToday, "开始今天")
        XCTAssertEqual(Strings.dayN(3), "第 3 天")
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.startToday, "Start today")
        XCTAssertEqual(Strings.dayN(3), "Day 3")
    }

    func testForcedLanguageUsesMatchingLocaleAndPureCopy() throws {
        let date = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 1, day: 5)))
        let style = Date.FormatStyle().month(.abbreviated).day()

        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertTrue(date.formatted(style.locale(AppLanguage.effective.locale)).contains("月"))
        XCTAssertEqual(Strings.notificationPrimerTitle, "留住今天的瞬间？")
        XCTAssertEqual(Strings.createFirstStory, "创建我的第一个故事")
        XCTAssertEqual(Strings.unitName(oneDay: true), "个瞬间")

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertTrue(date.formatted(style.locale(AppLanguage.effective.locale)).contains("Jan"))
        XCTAssertEqual(Strings.notificationPrimerTitle, "Keep today’s moment?")
        XCTAssertEqual(Strings.createFirstStory, "Create my first story")
        XCTAssertEqual(Strings.surfaceCamera, "Camera")
    }

    // MARK: MomentCatalog

    func testMomentCatalogResolvesKeysAndLegacyDisplayStrings() {
        XCTAssertEqual(MomentCatalog.localize("wake_up", .english), "Wake up")
        XCTAssertEqual(MomentCatalog.localize("wake_up", .chinese), "起床")
        // Legacy data stored the raw display string; both languages map back.
        XCTAssertEqual(MomentCatalog.localize("Wake up", .chinese), "起床")
        XCTAssertEqual(MomentCatalog.localize("起床", .english), "Wake up")
        // Unknown tokens pass through untouched.
        XCTAssertEqual(MomentCatalog.localize("My custom prompt", .english), "My custom prompt")
    }

    func testMomentCatalogKeyRoundTrip() {
        XCTAssertEqual(MomentCatalog.key(forDisplay: "Wake up"), "wake_up")
        XCTAssertEqual(MomentCatalog.key(forDisplay: "起床"), "wake_up")
        XCTAssertEqual(MomentCatalog.key(forDisplay: "wake_up"), "wake_up")
        XCTAssertNil(MomentCatalog.key(forDisplay: "Not a prompt"))
    }
}
