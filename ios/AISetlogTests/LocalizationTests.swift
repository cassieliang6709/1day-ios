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

    // MARK: Strings

    func testStringsSwitchWithStoredLanguage() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.startToday, "开始今天")
        XCTAssertEqual(Strings.dayN(3), "第 3 天")
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.startToday, "Start today")
        XCTAssertEqual(Strings.dayN(3), "Day 3")
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
