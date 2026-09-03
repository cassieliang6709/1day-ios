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

    /// - Parameter by: who filmed them. The header counts the day, not me, so
    ///   a room where only friends have filmed still reports progress.
    private func progress(recorded: Int, total: Int, by author: String = "local") -> RoomProgress {
        RoomProgress(
            momentCount: total,
            clips: (0..<recorded).map {
                DayClip(
                    day: $0 + 1,
                    url: URL(fileURLWithPath: "/tmp/clip\($0).mov"),
                    authorID: author)
            },
            myID: "me")
    }

    func testDateLineNamesTheDayInBothLanguages() {
        setLanguage(.chinese)
        let chinese = HomeHeaderSummary(date: september1, progress: nil)
        XCTAssertTrue(chinese.dateLine.contains("9"), chinese.dateLine)
        XCTAssertTrue(chinese.dateLine.contains("1"), chinese.dateLine)

        setLanguage(.english)
        let english = HomeHeaderSummary(date: september1, progress: nil)
        XCTAssertTrue(english.dateLine.contains("Sep"), english.dateLine)
        XCTAssertTrue(english.dateLine.contains("1"), english.dateLine)

        XCTAssertNotEqual(chinese.dateLine, english.dateLine)
    }

    func testNoActiveStoryLeavesProgressUnstatedRatherThanZero() {
        setLanguage(.english)
        let summary = HomeHeaderSummary(date: september1, progress: nil)
        XCTAssertNil(summary.recorded)
        XCTAssertNil(summary.total)
        XCTAssertFalse(summary.hasProgress)
        XCTAssertEqual(summary.progressLine, "")
    }

    func testProgressMatchesTheStorysRecordedCount() {
        setLanguage(.english)
        let summary = HomeHeaderSummary(
            date: september1, progress: progress(recorded: 1, total: 7))
        XCTAssertEqual(summary.recorded, 1)
        XCTAssertEqual(summary.total, 7)
        XCTAssertTrue(summary.hasProgress)
        XCTAssertEqual(summary.progressLine, "Today 1/7")

        setLanguage(.chinese)
        let chinese = HomeHeaderSummary(
            date: september1, progress: progress(recorded: 1, total: 7))
        XCTAssertEqual(chinese.progressLine, "今天 1/7")
    }

    /// The home screen's half of the "0/5" bug: a room three friends had been
    /// filming in all morning greeted the fourth person with "Today 0/5".
    func testAFriendsMomentsCountInTheHeader() {
        setLanguage(.english)
        let summary = HomeHeaderSummary(
            date: september1, progress: progress(recorded: 3, total: 5, by: "ana"))
        XCTAssertEqual(summary.progressLine, "Today 3/5")
    }

    /// A story with no slots would otherwise render "0/0", which reads as a
    /// real measurement of a day nobody has filmed.
    func testSlotlessStoryIsTreatedAsNoProgress() {
        setLanguage(.english)
        let summary = HomeHeaderSummary(
            date: september1, progress: progress(recorded: 0, total: 0))
        XCTAssertFalse(summary.hasProgress)
        XCTAssertNil(summary.recorded)
    }

    func testFinishedStoryReportsEveryMomentIn() {
        setLanguage(.english)
        let summary = HomeHeaderSummary(
            date: september1, progress: progress(recorded: 7, total: 7))
        XCTAssertEqual(summary.progressLine, "Today 7/7")
    }
}
