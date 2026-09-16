import XCTest
@testable import AISetlog

/// Nothing the app wrote itself should be in English when the app is in Chinese.
///
/// The bug this exists for was reported off a screenshot: a Chinese build with
/// English prompts showing under the moments. Chasing that one screenshot would
/// have fixed one prompt. `LocalizedText.zh` falls back to `.en` when a
/// translation is missing, which is the right behaviour for user-written text
/// and completely silent for shipped text — so the whole catalogue is swept
/// here instead, and a new prompt added without a translation fails a test
/// rather than reaching a Chinese phone in English.
///
/// The line this draws: **shipped copy must be translated, written copy must be
/// left alone.** A story someone named "Gym Week" stays "Gym Week" in both
/// languages, and `testUserEditedTitleIsNotTranslated...` in `LocalizationTests`
/// guards that side of it.
final class ChineseCopyPurityTests: XCTestCase {

    /// Latin letters in a string that is supposed to be Chinese. Digits,
    /// punctuation and emoji are all fine — "7 天" and "Wi-Fi" are not the
    /// problem, a whole untranslated prompt is.
    private func looksEnglish(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let latin = letters.filter { $0.value < 0x2E80 }
        // A majority, not a single character, so a brand name inside an
        // otherwise Chinese sentence doesn't trip it.
        return Double(latin.count) / Double(letters.count) > 0.5
    }

    // MARK: Moment prompts

    func testEveryBuiltInPromptHasARealChineseTranslation() {
        var untranslated: [String] = []
        for (key, entry) in MomentCatalog.entries {
            let zh = entry.text.zh
            if zh.isEmpty || zh == entry.text.en || looksEnglish(zh) {
                untranslated.append("\(key): \(zh)")
            }
        }
        XCTAssertTrue(
            untranslated.isEmpty,
            "prompts that would show in English on a Chinese phone: \(untranslated.sorted())")
    }

    func testEveryBuiltInPromptHasAnEnglishSideToo() {
        let missing = MomentCatalog.entries
            .filter { $0.value.text.en.isEmpty }
            .keys.sorted()
        XCTAssertTrue(missing.isEmpty, "prompts with no English: \(missing)")
    }

    // MARK: Templates

    func testEveryBuiltInTemplateIsNamedAndDescribedInChinese() {
        var untranslated: [String] = []
        for template in ChallengeTemplate.oneDayBuiltins + ChallengeTemplate.sevenDayBuiltins {
            // `liveWithMe` carries a stable identity key as its English name,
            // which is not display copy; its Chinese name is what shows.
            if template.name.zh.isEmpty || looksEnglish(template.name.zh) {
                untranslated.append("name \(template.name.en): \(template.name.zh)")
            }
            // A blurb is optional; one that exists has to be translated.
            if let blurb = template.blurb,
               blurb.zh.isEmpty || blurb.zh == blurb.en || looksEnglish(blurb.zh) {
                untranslated.append("blurb \(template.name.en): \(blurb.zh)")
            }
        }
        XCTAssertTrue(
            untranslated.isEmpty,
            "templates that would show in English on a Chinese phone: \(untranslated.sorted())")
    }

    /// A template whose key isn't in the catalogue falls through to the raw
    /// key — `wake_up` rather than 起床 — which is the other way English
    /// reaches a Chinese screen, and the one no amount of translating fixes.
    func testEveryTemplatePromptKeyResolvesInTheCatalogue() {
        var dangling: [String] = []
        for template in ChallengeTemplate.oneDayBuiltins + ChallengeTemplate.sevenDayBuiltins {
            for key in template.momentKeys ?? [] where MomentCatalog.entries[key] == nil {
                dangling.append("\(template.name.en) → \(key)")
            }
        }
        XCTAssertTrue(dangling.isEmpty, "prompt keys with no catalogue entry: \(dangling)")
    }

    // MARK: The rule itself

    /// The detector has to be trusted before its results mean anything.
    func testTheDetectorKnowsEnglishFromChinese() {
        XCTAssertTrue(looksEnglish("Wake up"))
        XCTAssertTrue(looksEnglish("Golden hour"))
        XCTAssertFalse(looksEnglish("起床"))
        XCTAssertFalse(looksEnglish("傍晚的光"))
        // Not a failure: numbers, punctuation and a stray brand word inside
        // Chinese copy are all normal.
        XCTAssertFalse(looksEnglish("7 天的故事"))
        XCTAssertFalse(looksEnglish("连上 Wi-Fi 之后再试一次，会接着删"))
        XCTAssertFalse(looksEnglish("2026"))
    }
}
