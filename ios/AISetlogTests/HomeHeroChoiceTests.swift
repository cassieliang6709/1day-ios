import XCTest
@testable import AISetlog

/// What the home screen leads with.
///
/// The bug these exist for: on 2026-09-01 a story filmed that morning was
/// nowhere on the home screen, because an empty story from three days earlier
/// had fewer moments filmed and the old rule was "fewest wins". Every case
/// below pins a chosen `now`, since the rule reads the clock.
final class HomeHeroChoiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    /// 2026-09-01, a Tuesday. Two times of day, because the rule differs.
    private func september1(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 1
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func daysBefore(_ days: Int, _ date: Date) -> Date {
        calendar.date(byAdding: .day, value: -days, to: date)!
    }

    /// `recorded` moments filmed out of `total`, each stamped `filmedAt`.
    private func story(
        _ title: String,
        startDate: Date,
        recorded: Int = 0,
        total: Int = 3,
        filmedAt: Date? = nil,
        mode: Challenge.Mode = .oneDay
    ) -> Challenge {
        Challenge(
            id: UUID(),
            title: title,
            startDate: startDate,
            cards: (1...total).map { day in
                DayCard(
                    day: day,
                    clipFileName: day <= recorded ? "clip\(day).mov" : nil,
                    recordedAt: day <= recorded ? (filmedAt ?? startDate) : nil)
            },
            mode: mode)
    }

    // MARK: - The reported bug

    func testTodaysStoryBeatsAnOlderUntouchedOne() {
        let now = september1(hour: 14)
        let today = story("今天", startDate: now, recorded: 1, filmedAt: now)
        let stale = story("三天前建的", startDate: daysBefore(3, now))

        let choice = HomeHeroChoice(
            challenges: [stale, today], now: now, calendar: calendar)

        XCTAssertEqual(choice, .today(today))
    }

    /// Same shape as above, before noon — the morning must not demote today
    /// either. This is the exact hour the bug was reported at.
    func testTodaysStoryWinsInTheMorningToo() {
        let now = september1(hour: 9)
        let today = story("今天", startDate: now, recorded: 1, filmedAt: now)
        let stale = story("三天前建的", startDate: daysBefore(3, now))

        let choice = HomeHeroChoice(
            challenges: [stale, today], now: now, calendar: calendar)

        XCTAssertEqual(choice.challenge?.id, today.id)
    }

    // MARK: - Seven-day challenges

    /// A week-long challenge on its fourth day is still what today is for,
    /// even though it started last Saturday.
    func testSevenDayChallengeMidWeekCountsAsToday() {
        let now = september1(hour: 15)
        let week = story(
            "一周",
            startDate: daysBefore(3, now),
            recorded: 3,
            total: 7,
            filmedAt: daysBefore(1, now),
            mode: .sevenDay)

        let choice = HomeHeroChoice(challenges: [week], now: now, calendar: calendar)

        XCTAssertEqual(choice, .today(week))
    }

    /// Past its last day, the same challenge is leftovers, not today's plan.
    func testSevenDayChallengePastItsWeekIsOnlySomethingToResume() {
        let now = september1(hour: 15)
        let week = story(
            "上上周的一周",
            startDate: daysBefore(9, now),
            recorded: 3,
            total: 7,
            filmedAt: daysBefore(7, now),
            mode: .sevenDay)

        let choice = HomeHeroChoice(challenges: [week], now: now, calendar: calendar)

        XCTAssertEqual(choice, .resume(week))
    }

    // MARK: - Time of day

    func testMorningWithYesterdaysUnfinishedStoryOffersToResume() {
        let now = september1(hour: 9)
        let yesterday = daysBefore(1, now)
        let leftover = story("昨天", startDate: yesterday, recorded: 1, filmedAt: yesterday)

        let choice = HomeHeroChoice(challenges: [leftover], now: now, calendar: calendar)

        XCTAssertEqual(choice, .resume(leftover))
    }

    /// Before noon, something from last week is not "the current thing" —
    /// the morning gets a clean slate.
    func testMorningWithOnlyOldStoriesOffersToStartToday() {
        let now = september1(hour: 9)
        let old = story("上周", startDate: daysBefore(6, now), recorded: 1)

        let choice = HomeHeroChoice(challenges: [old], now: now, calendar: calendar)

        XCTAssertEqual(choice, .startToday)
    }

    /// After noon it's the other way round: if the day is half gone and
    /// something is unfinished, that's what you'd pick back up.
    func testAfternoonWithAnyUnfinishedStoryOffersToResume() {
        let now = september1(hour: 15)
        let old = story("上周", startDate: daysBefore(6, now), recorded: 1)

        let choice = HomeHeroChoice(challenges: [old], now: now, calendar: calendar)

        XCTAssertEqual(choice, .resume(old))
    }

    // MARK: - Nothing to lead with

    func testNoStoriesAtAllOffersToStartToday() {
        let choice = HomeHeroChoice(
            challenges: [], now: september1(hour: 15), calendar: calendar)

        XCTAssertEqual(choice, .startToday)
    }

    func testEverythingFinishedOffersToStartToday() {
        let now = september1(hour: 15)
        let done = story("拍完了", startDate: now, recorded: 3, filmedAt: now)

        let choice = HomeHeroChoice(challenges: [done], now: now, calendar: calendar)

        XCTAssertEqual(choice, .startToday)
    }

    // MARK: - Tie-breaks

    /// Two stories both for today: the one being filmed wins.
    func testMostRecentlyFilmedWinsAmongTodaysStories() {
        let now = september1(hour: 16)
        let touched = story("刚拍过", startDate: now, recorded: 1, filmedAt: now)
        let untouched = story("建了没动", startDate: now)

        let choice = HomeHeroChoice(
            challenges: [untouched, touched], now: now, calendar: calendar)

        XCTAssertEqual(choice, .today(touched))
    }

    /// Nothing filmed in either: the one just set up wins, because that's the
    /// one the person was last looking at.
    func testNewestWinsWhenNothingHasBeenFilmed() {
        let now = september1(hour: 16)
        let earlier = story("早点建的", startDate: daysBefore(2, now), mode: .sevenDay)
        let later = story("刚建的", startDate: now)

        let choice = HomeHeroChoice(
            challenges: [earlier, later], now: now, calendar: calendar)

        XCTAssertEqual(choice, .today(later))
    }

    /// A story with no moments at all can't be led with — there'd be nothing
    /// to press. It shouldn't block a real one either.
    func testStoryWithNoMomentsIsIgnored() {
        let now = september1(hour: 16)
        let hollow = Challenge(
            id: UUID(), title: "空的", startDate: now, cards: [], mode: .oneDay)
        let real = story("真的", startDate: now)

        let choice = HomeHeroChoice(
            challenges: [hollow, real], now: now, calendar: calendar)

        XCTAssertEqual(choice, .today(real))
    }
}
