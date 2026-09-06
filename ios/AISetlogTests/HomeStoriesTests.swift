import XCTest
@testable import AISetlog

/// The whole home screen's story list, not either half of it.
///
/// `HomeHeroChoice` and `StoryTimeline` were each correct on their own and
/// still produced a screen where a story you just made had no section named
/// after it: the hero is lifted out of the timeline, so on the one day you
/// create a story the leftover list is all older days and gets headed
/// 「往前翻」. These pin the two facts that matter — every story is reachable,
/// and the list is called what it is.
final class HomeStoriesTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        super.tearDown()
    }

    /// 2026-09-01 is a Tuesday.
    private func september(_ day: Int, hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour))!
    }

    private func august(_ day: Int, hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 8, day: day, hour: hour))!
    }

    /// `recorded` moments filmed out of `total`. `recorded: 0` is the story in
    /// the bug report: made, never filmed.
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

    /// Every id the screen shows anywhere — hero card plus every list row.
    private func shown(_ home: HomeStories) -> Set<UUID> {
        var ids = Set(home.timeline.days.flatMap { $0.stories.map(\.id) })
        if let hero = home.hero.challenge { ids.insert(hero.id) }
        return ids
    }

    // MARK: - The reported bug: "even unfilmed, it should be in my stories"

    /// The report, exactly: make a story, film nothing, go home. The list it
    /// belongs to has to be called 「你的故事」 — not 「往前翻」, which is where
    /// someone looking for what they just made will never think to look.
    func testTheListIsCalledYourStoriesWhenTodaysStoryIsOnScreen() {
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        let now = september(1)
        let justMade = story("刚建的", on: now)
        let lastWeek = story("上周", on: august(24), recorded: 3)

        let home = home([justMade, lastWeek], now: now)

        XCTAssertEqual(home.hero.challenge?.id, justMade.id)
        XCTAssertEqual(home.sectionTitle, Strings.yourStories)
    }

    /// The same screen in English, so the fix isn't a Chinese-only string.
    func testTheListIsCalledYourStoriesInEnglishToo() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        let now = september(1)

        let home = home(
            [story("just made", on: now), story("last week", on: august(24), recorded: 3)],
            now: now)

        XCTAssertEqual(home.sectionTitle, Strings.yourStories)
    }

    /// An unfilmed story is on the screen somewhere. This is the invariant the
    /// bug report is really about, and it has to hold whatever else is around.
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

    /// Morning and evening take different branches through the hero rule, so
    /// the invariant is checked on both sides of noon.
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

    /// Nothing is on the screen twice: the hero is lifted out of the list
    /// rather than repeated, which is the behaviour this fix must not undo.
    func testTheHeroIsNotAlsoAListRow() {
        let now = september(1)
        let hero = story("今天", on: now)
        let older = story("上周", on: august(24), recorded: 3)

        let home = home([hero, older], now: now)

        XCTAssertEqual(home.hero.challenge?.id, hero.id)
        XCTAssertFalse(
            home.timeline.days.flatMap { $0.stories.map(\.id) }.contains(hero.id))
    }

    /// Every story, filmed or not, hero or row — nothing dropped, nothing
    /// duplicated. The strongest form of "it should be visible".
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

    /// One story, never filmed, nothing else. It's the hero, so there's no
    /// list at all — and that's the one case where "it's in your stories" has
    /// to mean the card at the top rather than a row.
    func testASingleUnfilmedStoryIsTheHeroAndTheListIsEmpty() {
        let now = september(1)
        let only = story("唯一一个", on: now)

        let home = home([only], now: now)

        XCTAssertEqual(home.hero.challenge?.id, only.id)
        XCTAssertTrue(home.timeline.isEmpty)
        XCTAssertFalse(home.showsSection)
    }

    /// No stories at all: no section, no heading, no crash.
    func testAnEmptyShelfShowsNoSection() {
        let home = home([], now: september(1))

        XCTAssertNil(home.hero.challenge)
        XCTAssertTrue(home.timeline.isEmpty)
        XCTAssertFalse(home.showsSection)
    }

    // MARK: - A story with no moments at all

    /// `isComplete` is `recorded == cards.count`, which is vacuously true when
    /// there are no cards — so a zero-moment story reads as "finished" and is
    /// barred from the hero. It still has to appear in the list rather than
    /// falling through both.
    func testAStoryWithNoMomentsStillAppears() {
        let now = september(1)
        let empty = Challenge(
            id: UUID(), title: "没有格子", startDate: now, cards: [], mode: .oneDay)

        let home = home([empty], now: now)

        XCTAssertTrue(shown(home).contains(empty.id))
    }
}
