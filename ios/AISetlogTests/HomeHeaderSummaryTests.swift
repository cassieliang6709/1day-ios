import XCTest
@testable import AISetlog

/// The home header's date line. These used to be inline in the
/// view, where the only way to check them was to look at a simulator in two
/// languages.
final class HomeHeaderSummaryTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    private func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
    }

    /// 2026-09-01, a Tuesday — the day the missing-date problem was reported.
    private var september1: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 1
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testDateLineNamesTheDayInBothLanguages() {
        setLanguage(.chinese)
        let chinese = HomeHeaderSummary(date: september1)
        XCTAssertTrue(chinese.dateLine.contains("9"), chinese.dateLine)
        XCTAssertTrue(chinese.dateLine.contains("1"), chinese.dateLine)

        setLanguage(.english)
        let english = HomeHeaderSummary(date: september1)
        XCTAssertTrue(english.dateLine.contains("Sep"), english.dateLine)
        XCTAssertTrue(english.dateLine.contains("1"), english.dateLine)

        XCTAssertNotEqual(chinese.dateLine, english.dateLine)
    }
}
