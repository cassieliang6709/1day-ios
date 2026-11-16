import XCTest
@testable import AISetlog

final class ChineseCopyPurityTests: XCTestCase {

    private func looksEnglish(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let latin = letters.filter { $0.value < 0x2E80 }
        return Double(latin.count) / Double(letters.count) > 0.5
    }


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


    func testEverySuggestedMomentKeyResolvesInTheCatalogue() {
        let dangling = MomentCatalog.suggestionPool.filter { MomentCatalog.entries[$0] == nil }
        XCTAssertTrue(dangling.isEmpty, "suggestion keys with no catalogue entry: \(dangling)")
    }


    func testTheDetectorKnowsEnglishFromChinese() {
        XCTAssertTrue(looksEnglish("Wake up"))
        XCTAssertTrue(looksEnglish("Golden hour"))
        XCTAssertFalse(looksEnglish("起床"))
        XCTAssertFalse(looksEnglish("傍晚的光"))
        XCTAssertFalse(looksEnglish("7 天的故事"))
        XCTAssertFalse(looksEnglish("连上 Wi-Fi 之后再试一次，会接着删"))
        XCTAssertFalse(looksEnglish("2026"))
    }
}
