import XCTest
@testable import AISetlog

/// Scrolling back through the days. Home used to group by state — in progress
/// and finished — which can't answer "what did I film on the 31st". These pin
/// the grouping, the order, and the fact that today's story doesn't appear
/// twice on one screen.
final class StoryTimelineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    /// 2026-09-01 is a Tuesday.
    private func september(_ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour))!
    }

    private func august(_ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 8, day: day, hour: hour))!
    }

    private func story(
        _ title: String,
        on date: Date,
        recorded: Int = 0,
        total: Int = 3,
        filmedAt: Date? = nil
    ) -> Challenge {
        Challenge(
            id: UUID(),
            title: title,
            startDate: date,
            cards: (1...total).map { day in
                DayCard(
                    day: day,
                    clipFileName: day <= recorded ? "clip\(day).mov" : nil,
                    recordedAt: day <= recorded ? (filmedAt ?? date) : nil)
            },
            mode: .oneDay)
    }

    // MARK: - Grouping

    func testStoriesFromTheSameDayLandInOneGroup() {
        let morning = story("早上", on: september(1, hour: 8))
        let evening = story("晚上", on: september(1, hour: 21))

        let timeline = StoryTimeline(
            challenges: [morning, evening], now: september(1), calendar: calendar)

        XCTAssertEqual(timeline.days.count, 1)
        XCTAssertEqual(timeline.days.first?.stories.count, 2)
    }

    func testDaysComeBackNewestFirst() {
        let timeline = StoryTimeline(
            challenges: [
                story("24 号", on: august(24)),
                story("31 号", on: august(31)),
                story("29 号", on: august(29)),
            ],
            now: september(1),
            calendar: calendar)

        XCTAssertEqual(
            timeline.days.map(\.date),
            [
                calendar.startOfDay(for: august(31)),
                calendar.startOfDay(for: august(29)),
                calendar.startOfDay(for: august(24)),
            ])
    }

    /// Finished and unfinished sit together: "when" is the axis, not "how far
    /// along". The old two-list split is exactly what this replaces.
    func testFinishedAndUnfinishedShareADay() {
        let done = story("拍完了", on: august(31), recorded: 3, total: 3)
        let notDone = story("没拍完", on: august(31), recorded: 1, total: 3)

        let timeline = StoryTimeline(
            challenges: [done, notDone], now: september(1), calendar: calendar)

        XCTAssertEqual(timeline.days.count, 1)
        XCTAssertEqual(timeline.days.first?.stories.count, 2)
    }

    /// Within a day, whatever was filmed most recently reads first.
    func testMostRecentlyFilmedComesFirstWithinADay() {
        let early = story("早拍的", on: august(31), recorded: 1, filmedAt: august(31, hour: 9))
        let late = story("晚拍的", on: august(31), recorded: 1, filmedAt: august(31, hour: 22))

        let timeline = StoryTimeline(
            challenges: [early, late], now: september(1), calendar: calendar)

        XCTAssertEqual(timeline.days.first?.stories.map(\.id), [late.id, early.id])
    }

    // MARK: - The hero

    func testTheHeroStoryIsNotRepeatedInTheTimeline() {
        let hero = story("今天", on: september(1))
        let older = story("上周", on: august(24))

        let timeline = StoryTimeline(
            challenges: [hero, older],
            excluding: hero.id,
            now: september(1),
            calendar: calendar)

        XCTAssertEqual(timeline.days.count, 1)
        XCTAssertEqual(timeline.days.first?.stories.map(\.id), [older.id])
    }

    /// A day that had only the hero in it disappears entirely, rather than
    /// leaving an empty date label behind.
    func testADayEmptiedByTheHeroDoesNotAppear() {
        let hero = story("今天", on: september(1))

        let timeline = StoryTimeline(
            challenges: [hero],
            excluding: hero.id,
            now: september(1),
            calendar: calendar)

        XCTAssertTrue(timeline.isEmpty)
        XCTAssertTrue(timeline.days.isEmpty)
    }

    func testNoStoriesGivesAnEmptyTimelineRatherThanCrashing() {
        let timeline = StoryTimeline(
            challenges: [], now: september(1), calendar: calendar)

        XCTAssertTrue(timeline.isEmpty)
    }

    // MARK: - Labels

    func testTodayAndYesterdayAreNamedNotDated() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)

        let timeline = StoryTimeline(
            challenges: [
                story("今天", on: september(2)),
                story("昨天", on: september(1)),
                story("前天", on: august(31)),
            ],
            now: september(2),
            calendar: calendar)

        XCTAssertEqual(timeline.days.map(\.label).prefix(2), ["今天", "昨天"])
        XCTAssertNotEqual(timeline.days.last?.label, "前天")
    }

    /// The heading above the list. "Scroll back" directly above a row labelled
    /// "today" claims something about the contents that isn't true.
    func testTheListKnowsWhetherTodayIsInIt() {
        let today = story("今天", on: september(1))
        let older = story("上周", on: august(24))

        XCTAssertTrue(
            StoryTimeline(challenges: [today, older], now: september(1), calendar: calendar)
                .includesToday)
        XCTAssertFalse(
            StoryTimeline(challenges: [older], now: september(1), calendar: calendar)
                .includesToday)
        XCTAssertFalse(
            StoryTimeline(
                challenges: [today], excluding: today.id,
                now: september(1), calendar: calendar
            ).includesToday)
    }

    func testOlderDaysCarryTheirDateInBothLanguages() {
        // Not the 31st: that's "yesterday" relative to the 1st, and yesterday
        // is named rather than dated.
        let stories = [story("上周", on: august(24))]

        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        let chinese = StoryTimeline(
            challenges: stories, now: september(1), calendar: calendar)
            .days.first?.label ?? ""

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        let english = StoryTimeline(
            challenges: stories, now: september(1), calendar: calendar)
            .days.first?.label ?? ""

        XCTAssertTrue(chinese.contains("24"), chinese)
        XCTAssertTrue(english.contains("24"), english)
        XCTAssertTrue(english.contains("Aug"), english)
        XCTAssertNotEqual(chinese, english)
    }

    /// A seven-day challenge hangs off the day it started, whole — scattering
    /// one film across seven entries would bury the thing you came for.
    func testASevenDayChallengeSitsOnOneDay() {
        let week = Challenge(
            id: UUID(),
            title: "一周",
            startDate: august(26),
            cards: (1...7).map {
                DayCard(
                    day: $0,
                    clipFileName: $0 <= 4 ? "clip\($0).mov" : nil,
                    recordedAt: $0 <= 4 ? august(25 + $0) : nil)
            },
            mode: .sevenDay)

        let timeline = StoryTimeline(
            challenges: [week], now: september(1), calendar: calendar)

        XCTAssertEqual(timeline.days.count, 1)
        XCTAssertEqual(timeline.days.first?.date, calendar.startOfDay(for: august(26)))
    }
}
