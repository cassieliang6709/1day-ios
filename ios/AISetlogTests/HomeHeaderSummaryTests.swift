import XCTest
@testable import AISetlog

/// The home header's date and progress line. These used to be inline in the
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

    private func challenge(recorded: Int, total: Int) -> Challenge {
        Challenge(
            id: UUID(),
            title: "Perfect day",
            startDate: .now,
            cards: (1...total).map {
                DayCard(day: $0, clipFileName: $0 <= recorded ? "clip\($0).mov" : nil)
            },
            mode: .oneDay)
    }

    func testDateLineNamesTheDayInBothLanguages() {
        setLanguage(.chinese)
        let chinese = HomeHeaderSummary(date: september1, challenge: nil)
        XCTAssertTrue(chinese.dateLine.contains("9"), chinese.dateLine)
        XCTAssertTrue(chinese.dateLine.contains("1"), chinese.dateLine)

        setLanguage(.english)
        let english = HomeHeaderSummary(date: september1, challenge: nil)
        XCTAssertTrue(english.dateLine.contains("Sep"), english.dateLine)
        XCTAssertTrue(english.dateLine.contains("1"), english.dateLine)

        XCTAssertNotEqual(chinese.dateLine, english.dateLine)
    }

    func testNoActiveStoryLeavesProgressUnstatedRatherThanZero() {
        setLanguage(.english)
        let summary = HomeHeaderSummary(date: september1, challenge: nil)
        XCTAssertNil(summary.recorded)
        XCTAssertNil(summary.total)
        XCTAssertFalse(summary.hasProgress)
        XCTAssertEqual(summary.progressLine, "")
    }

    func testProgressMatchesTheStorysRecordedCount() {
        setLanguage(.english)
        let summary = HomeHeaderSummary(
            date: september1, challenge: challenge(recorded: 1, total: 7))
        XCTAssertEqual(summary.recorded, 1)
        XCTAssertEqual(summary.total, 7)
        XCTAssertTrue(summary.hasProgress)
        XCTAssertEqual(summary.progressLine, "Today 1/7")

        setLanguage(.chinese)
        let chinese = HomeHeaderSummary(
            date: september1, challenge: challenge(recorded: 1, total: 7))
        XCTAssertEqual(chinese.progressLine, "今天 1/7")
    }

    /// A story with no slots would otherwise render "0/0", which reads as a
    /// real measurement of a day nobody has filmed.
    func testSlotlessStoryIsTreatedAsNoProgress() {
        setLanguage(.english)
        let empty = Challenge(
            id: UUID(), title: "Broken", startDate: .now, cards: [], mode: .oneDay)
        let summary = HomeHeaderSummary(date: september1, challenge: empty)
        XCTAssertFalse(summary.hasProgress)
        XCTAssertNil(summary.recorded)
    }

    func testFinishedStoryReportsEveryMomentIn() {
        setLanguage(.english)
        let summary = HomeHeaderSummary(
            date: september1, challenge: challenge(recorded: 7, total: 7))
        XCTAssertEqual(summary.progressLine, "Today 7/7")
    }
}
