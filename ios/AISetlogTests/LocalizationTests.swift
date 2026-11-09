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

    // MARK: Story titles

    /// 按时间拍 is stored under the old template's name, so every saved story
    /// and room keeps reading as time-only after templates went away (1.5).
    func testTimeOnlyIsReadFromTheStoredTemplateName() {
        let byTime = Challenge(
            id: UUID(), title: "10月19日", startDate: .now, cards: [DayCard(day: 1)],
            mode: .oneDay, templateName: Challenge.timeOnlyTemplateName)
        XCTAssertTrue(byTime.isTimeOnly)
        XCTAssertEqual(Challenge.timeOnlyTemplateName, "Live With Me")

        let oldTemplate = Challenge(
            id: UUID(), title: "Soft Reset", startDate: .now, cards: [DayCard(day: 1)],
            mode: .oneDay, templateName: "Soft Reset")
        XCTAssertFalse(oldTemplate.isTimeOnly)
    }

    /// A name is shown as it was saved — no template swaps it into the app's
    /// language any more.
    func testDisplayTitleIsTheSavedTitle() {
        let challenge = Challenge(
            id: UUID(), title: "Soft Reset", startDate: .now, cards: [DayCard(day: 1)],
            mode: .oneDay, templateName: "Soft Reset")
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(ChallengePresenter(challenge: challenge).displayTitle, "Soft Reset")
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

    /// The composer's new copy. Shipping any of it in one language only would
    /// leave the other with a grey grid, or a count, and no words around it.
    func testComposerPromptCopyIsWrittenInBothLanguages() {
        func inBothLanguages(_ string: () -> String) -> (String, String) {
            UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
            let chinese = string()
            UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
            return (chinese, string())
        }

        let pairs = [
            inBothLanguages { Strings.followPrompts },
            inBothLanguages { Strings.recordByTime },
            inBothLanguages { Strings.coverFromClips },
            inBothLanguages { Strings.previewTheFilm(7) },
        ]

        for (chinese, english) in pairs {
            XCTAssertFalse(chinese.isEmpty)
            XCTAssertFalse(english.isEmpty)
            XCTAssertNotEqual(chinese, english)
        }
    }

    /// "Preview · 1 moments" shipped, and shipped for a while, because every
    /// caller wrote the English plural in by hand and nobody opened a story
    /// with exactly one moment filmed in it.
    func testEnglishCountsAgreeWithTheirNoun() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)

        XCTAssertEqual(Strings.previewTheFilm(1), "Preview · 1 moment")
        XCTAssertEqual(Strings.previewTheFilm(2), "Preview · 2 moments")
        XCTAssertEqual(Strings.momentsShort(1), "1 moment")
        XCTAssertEqual(Strings.momentsShort(7), "7 moments")
        XCTAssertEqual(Strings.momentCount(1), "1 moment in 24 hours")

        // Chinese has no plural, so the same call has to stay unchanged there.
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.previewTheFilm(1), "预览 · 1 个瞬间")
        XCTAssertEqual(Strings.momentsShort(7), "7 个瞬间")
    }

    /// 原来用的 promptCountLabel 和 createFirstStory 已经删了 —— 界面上
    /// 没有任何地方用它们。换成两条真的在用的，测的还是同一件事：数字要
    /// 带得出来，强制语言要生效。
    func testPromptCountAndProgressCarryTheirNumbers() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.previewTheFilm(7), "预览 · 7 个瞬间")

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.previewTheFilm(7), "Preview · 7 moments")
    }

    func testForcedLanguageUsesMatchingLocaleAndPureCopy() throws {
        let date = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 1, day: 5)))
        let style = Date.FormatStyle().month(.abbreviated).day()

        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertTrue(date.formatted(style.locale(AppLanguage.effective.locale)).contains("月"))
        XCTAssertEqual(Strings.notificationPrimerTitle, "留住今天的瞬间？")
        XCTAssertEqual(Strings.startTodaysStory, "今天想拍什么")
        XCTAssertEqual(Strings.unitName(oneDay: true), "个瞬间")

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertTrue(date.formatted(style.locale(AppLanguage.effective.locale)).contains("Jan"))
        XCTAssertEqual(Strings.notificationPrimerTitle, "Keep today’s moment?")
        // Typewriter apostrophe, matching the string as shipped. Most of the
        // English copy uses one; a handful use the curly ’ instead.
        XCTAssertEqual(Strings.startTodaysStory, "What to film today")
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
