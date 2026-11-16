import XCTest
@testable import AISetlog

final class HomeStoriesTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    private func september(_ day: Int, hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour))!
    }

    private func august(_ day: Int, hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 8, day: day, hour: hour))!
    }

    private func story(
        _ title: String,
        on date: Date,
        recorded: Int = 0,
        total: Int = 3,
        filmedAt: Date? = nil,
        mode: Challenge.Mode = .oneDay
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
            mode: mode)
    }

    private func home(_ challenges: [Challenge], now: Date) -> HomeStories {
        HomeStories(challenges: challenges, now: now, calendar: calendar)
    }

    private func shown(_ home: HomeStories) -> Set<UUID> {
        var ids = Set(home.timeline.days.flatMap { $0.stories.map(\.id) })
        if let hero = home.hero.challenge { ids.insert(hero.id) }
        return ids
    }


    func testTheListIsCalledYourStoriesWhenTodaysStoryIsOnScreen() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        let now = september(1)
        let justMade = story("刚建的", on: now)
        let lastWeek = story("上周", on: august(24), recorded: 3)

        let home = home([justMade, lastWeek], now: now)

        XCTAssertEqual(home.hero.challenge?.id, justMade.id)
        XCTAssertEqual(home.sectionTitle, Strings.yourStories)
    }

    func testTheListIsCalledYourStoriesInEnglishToo() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        let now = september(1)

        let home = home(
            [story("just made", on: now), story("last week", on: august(24), recorded: 3)],
            now: now)

        XCTAssertEqual(home.sectionTitle, Strings.yourStories)
    }

    func testAnUnfilmedStoryIsAlwaysOnTheScreen() {
        let now = september(1)
        let unfilmed = story("没拍过", on: now)

        let neighbours: [(String, [Challenge])] = [
            ("alone", []),
            ("with an older finished story", [story("上周", on: august(24), recorded: 3)]),
            ("with another story filmed today",
             [story("今天拍过的", on: now, recorded: 2, filmedAt: now)]),
            ("with a finished story from today",
             [story("今天拍完的", on: now, recorded: 3, filmedAt: now)]),
            ("with an unfilmed story from yesterday",
             [story("昨天建的", on: august(31))]),
            ("with a seven-day week in progress",
             [story("这周", on: august(27), recorded: 2, total: 7,
                    filmedAt: august(29), mode: .sevenDay)]),
        ]

        for (label, others) in neighbours {
            let home = home([unfilmed] + others, now: now)
            XCTAssertTrue(
                shown(home).contains(unfilmed.id),
                "an unfilmed story vanished from home \(label)")
        }
    }

    func testAnUnfilmedStoryIsOnTheScreenAtEveryHour() {
        let unfilmedYesterday = story("昨天建的没拍", on: august(31, hour: 20))
        let older = story("上周", on: august(24), recorded: 3)

        for hour in [0, 6, 9, 11, 12, 13, 18, 23] {
            let now = september(1, hour: hour)
            let home = home([unfilmedYesterday, older], now: now)
            XCTAssertTrue(
                shown(home).contains(unfilmedYesterday.id),
                "an unfilmed story vanished from home at \(hour):00")
        }
    }

    func testTheHeroIsNotAlsoAListRow() {
        let now = september(1)
        let hero = story("今天", on: now)
        let older = story("上周", on: august(24), recorded: 3)

        let home = home([hero, older], now: now)

        XCTAssertEqual(home.hero.challenge?.id, hero.id)
        XCTAssertFalse(
            home.timeline.days.flatMap { $0.stories.map(\.id) }.contains(hero.id))
    }

    func testEveryStoryIsShownExactlyOnce() {
        let now = september(1)
        let all = [
            story("今天没拍", on: now),
            story("今天拍了一半", on: now, recorded: 1, filmedAt: now),
            story("今天拍完", on: now, recorded: 3, filmedAt: now),
            story("昨天没拍", on: august(31)),
            story("上周拍完", on: august(24), recorded: 3),
            story("这周", on: august(27), recorded: 2, total: 7,
                  filmedAt: august(29), mode: .sevenDay),
        ]

        let home = home(all, now: now)
        var rows = home.timeline.days.flatMap { $0.stories.map(\.id) }
        if let hero = home.hero.challenge { rows.append(hero.id) }

        XCTAssertEqual(Set(rows), Set(all.map(\.id)))
        XCTAssertEqual(rows.count, all.count, "a story appeared twice")
    }

    func testASingleUnfilmedStoryIsTheHeroAndTheListIsEmpty() {
        let now = september(1)
        let only = story("唯一一个", on: now)

        let home = home([only], now: now)

        XCTAssertEqual(home.hero.challenge?.id, only.id)
        XCTAssertTrue(home.timeline.isEmpty)
        XCTAssertFalse(home.showsSection)
    }

    func testAnEmptyShelfShowsNoSection() {
        let home = home([], now: september(1))

        XCTAssertNil(home.hero.challenge)
        XCTAssertTrue(home.timeline.isEmpty)
        XCTAssertFalse(home.showsSection)
    }


    func testTheHeadingIsHiddenWhenNothingInTheListIsFilmed() {
        let now = september(1)
        let today = story("今天建的", on: now)
        let yesterday = story("昨天建的", on: august(31))

        let home = home([today, yesterday], now: now)

        XCTAssertTrue(home.showsSection, "the row still has to be reachable")
        XCTAssertNil(home.sectionTitle)
    }

    func testOneFilmedRowBringsTheHeadingBack() {
        let now = september(1)
        let today = story("今天建的", on: now)
        let yesterday = story("昨天拍过", on: august(31), recorded: 1)

        let home = home([today, yesterday], now: now)

        XCTAssertEqual(home.sectionTitle, Strings.yourStories)
    }

    func testFilmingOnlyTheHeroLeavesTheHeadingHidden() {
        let now = september(1)
        let today = story("今天拍过", on: now, recorded: 1, filmedAt: now)
        let yesterday = story("昨天建的", on: august(31))

        let home = home([today, yesterday], now: now)

        XCTAssertEqual(home.hero.challenge?.id, today.id)
        XCTAssertEqual(home.timeline.days.flatMap { $0.stories }.map(\.id), [yesterday.id])
        XCTAssertNil(home.sectionTitle)
    }


    func testAStoryWithNoMomentsStillAppears() {
        let now = september(1)
        let empty = Challenge(
            id: UUID(), title: "没有格子", startDate: now, cards: [], mode: .oneDay)

        let home = home([empty], now: now)

        XCTAssertTrue(shown(home).contains(empty.id))
    }
}
