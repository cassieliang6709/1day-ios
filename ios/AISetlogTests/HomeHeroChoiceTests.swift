import XCTest
@testable import AISetlog

final class HomeHeroChoiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

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


    func testTodaysStoryBeatsAnOlderUntouchedOne() {
        let now = september1(hour: 14)
        let today = story("今天", startDate: now, recorded: 1, filmedAt: now)
        let stale = story("三天前建的", startDate: daysBefore(3, now))

        let choice = HomeHeroChoice(
            challenges: [stale, today], now: now, calendar: calendar)

        XCTAssertEqual(choice, .today(today))
    }

    func testTodaysStoryWinsInTheMorningToo() {
        let now = september1(hour: 9)
        let today = story("今天", startDate: now, recorded: 1, filmedAt: now)
        let stale = story("三天前建的", startDate: daysBefore(3, now))

        let choice = HomeHeroChoice(
            challenges: [stale, today], now: now, calendar: calendar)

        XCTAssertEqual(choice.challenge?.id, today.id)
    }


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


    func testMorningWithYesterdaysUnfinishedStoryOffersToResume() {
        let now = september1(hour: 9)
        let yesterday = daysBefore(1, now)
        let leftover = story("昨天", startDate: yesterday, recorded: 1, filmedAt: yesterday)

        let choice = HomeHeroChoice(challenges: [leftover], now: now, calendar: calendar)

        XCTAssertEqual(choice, .resume(leftover))
    }

    func testMorningWithOnlyOldStoriesOffersToStartToday() {
        let now = september1(hour: 9)
        let old = story("上周", startDate: daysBefore(6, now), recorded: 1)

        let choice = HomeHeroChoice(challenges: [old], now: now, calendar: calendar)

        XCTAssertEqual(choice, .startToday)
    }

    func testAfternoonWithAnyUnfinishedStoryOffersToResume() {
        let now = september1(hour: 15)
        let old = story("上周", startDate: daysBefore(6, now), recorded: 1)

        let choice = HomeHeroChoice(challenges: [old], now: now, calendar: calendar)

        XCTAssertEqual(choice, .resume(old))
    }


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


    func testMostRecentlyFilmedWinsAmongTodaysStories() {
        let now = september1(hour: 16)
        let touched = story("刚拍过", startDate: now, recorded: 1, filmedAt: now)
        let untouched = story("建了没动", startDate: now)

        let choice = HomeHeroChoice(
            challenges: [untouched, touched], now: now, calendar: calendar)

        XCTAssertEqual(choice, .today(touched))
    }

    func testNewestWinsWhenNothingHasBeenFilmed() {
        let now = september1(hour: 16)
        let earlier = story("早点建的", startDate: daysBefore(2, now), mode: .sevenDay)
        let later = story("刚建的", startDate: now)

        let choice = HomeHeroChoice(
            challenges: [earlier, later], now: now, calendar: calendar)

        XCTAssertEqual(choice, .today(later))
    }

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
