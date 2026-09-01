import XCTest
@testable import AISetlog

final class NotificationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testOneDayChallengeSchedulesOnlyOneReminder() throws {
        let now = try date(2026, 7, 25, 12, 0)
        let challenge = makeChallenge(
            title: "Saturday",
            startDate: now,
            mode: .oneDay,
            cardCount: 7)

        let plans = ReminderService.plannedReminders(
            for: [challenge],
            now: now,
            calendar: calendar,
            hour: 20,
            minute: 30)

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.challengeID, challenge.id)
        XCTAssertEqual(plans.first?.day, 1)
        XCTAssertEqual(plans.first?.fireDate, try date(2026, 7, 25, 20, 30))
    }

    func testReminderPlanningSkipsRecordedAndPastMoments() throws {
        let start = try date(2026, 7, 25, 9, 0)
        let now = try date(2026, 7, 25, 21, 0)
        let challenge = makeChallenge(
            title: "Week",
            startDate: start,
            mode: .sevenDay,
            cardCount: 7,
            recordedDays: [2])

        let plans = ReminderService.plannedReminders(
            for: [challenge],
            now: now,
            calendar: calendar,
            hour: 20,
            minute: 30)

        XCTAssertEqual(plans.map(\.day), [3, 4, 5, 6, 7])
        XCTAssertTrue(plans.allSatisfy { $0.fireDate > now })
    }

    func testSharedChallengeWinsWhenTwoChallengesNeedSameDay() throws {
        let now = try date(2026, 7, 25, 12, 0)
        let local = makeChallenge(
            title: "Solo",
            startDate: now,
            mode: .sevenDay,
            cardCount: 3)
        let shared = makeChallenge(
            title: "Together",
            startDate: now,
            mode: .sevenDay,
            cardCount: 3,
            roomCode: "ABCDEF")

        let plans = ReminderService.plannedReminders(
            for: [local, shared],
            now: now,
            calendar: calendar,
            hour: 20,
            minute: 30)

        XCTAssertEqual(plans.count, 3)
        XCTAssertEqual(Set(plans.map(\.challengeID)), [shared.id])
    }

    func testTimeOnlyReminderDoesNotInventADayOrPromptTitle() throws {
        let now = try date(2026, 7, 25, 12, 0)
        let challenge = makeChallenge(
            title: "Live With Me",
            startDate: now,
            mode: .oneDay,
            cardCount: 7,
            templateName: ChallengeTemplate.liveWithMeIdentityKey)

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey) }
        let plan = ReminderService.plannedReminders(
            for: [challenge], now: now, calendar: calendar, hour: 20, minute: 30).first

        XCTAssertEqual(plan?.body, Strings.timeOnlyReminder)
        XCTAssertFalse(plan?.body.contains("Day") == true)
    }

    func testNotificationRouteParsesCloudKitPayload() {
        let id = UUID()
        let route = NotificationRecordRoute(userInfo: [
            NotificationConstants.challengeIDKey: id.uuidString,
            NotificationConstants.dayKey: NSNumber(value: 4),
        ])

        XCTAssertEqual(route, NotificationRecordRoute(challengeID: id, day: 4))
    }

    private func makeChallenge(
        title: String,
        startDate: Date,
        mode: Challenge.Mode,
        cardCount: Int,
        recordedDays: Set<Int> = [],
        roomCode: String? = nil,
        templateName: String? = nil
    ) -> Challenge {
        var cards = (1...cardCount).map { DayCard(day: $0) }
        for index in cards.indices where recordedDays.contains(cards[index].day) {
            cards[index].clipFileName = "day\(cards[index].day).mov"
        }
        return Challenge(
            id: UUID(),
            title: title,
            startDate: startDate,
            cards: cards,
            mode: mode,
            templateName: templateName,
            roomCode: roomCode)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute)))
    }
}
