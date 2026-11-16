import XCTest
@testable import AISetlog

final class HomeHeaderSummaryTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    private func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
    }

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
