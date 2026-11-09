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
            templateName: Challenge.timeOnlyTemplateName)

        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey) }
        let plan = ReminderService.plannedReminders(
            for: [challenge], now: now, calendar: calendar, hour: 20, minute: 30).first

        XCTAssertEqual(plan?.body, Strings.timeOnlyReminder)
        XCTAssertFalse(plan?.body.contains("Day") == true)
    }

    /// A room doesn't number its days on screen (1.5), so its reminders
    /// can't either; a solo week still says which day it is.
    func testSharedRoomReminderNamesNoDay() throws {
        let now = try date(2026, 7, 25, 12, 0)
        let shared = makeChallenge(
            title: "Together", startDate: now, mode: .sevenDay, cardCount: 3,
            roomCode: "ABCDEF")
        let solo = makeChallenge(
            title: "Solo", startDate: now, mode: .sevenDay, cardCount: 3)

        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey) }
        let roomPlans = ReminderService.plannedReminders(
            for: [shared], now: now, calendar: calendar, hour: 20, minute: 30)
        let soloPlans = ReminderService.plannedReminders(
            for: [solo], now: now, calendar: calendar, hour: 20, minute: 30)

        XCTAssertFalse(roomPlans.isEmpty)
        XCTAssertTrue(roomPlans.allSatisfy { $0.body == Strings.roomReminderBody(prompt: nil) })
        XCTAssertTrue(roomPlans.allSatisfy { !$0.body.contains("天") })
        XCTAssertTrue(soloPlans.allSatisfy { $0.body.contains("第 \($0.day) 天") })
    }

    /// The push for a friend's clip says who, not which day.
    func testRoomClipActivityNamesNoDay() {
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey) }
        UserDefaults.standard.set(AppLanguage.chinese.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.roomClipActivity(name: "小蓝"), "小蓝 刚拍了一段")
        XCTAssertEqual(Strings.roomClipActivity(name: nil), "有人刚拍了一段")
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        XCTAssertEqual(Strings.roomClipActivity(name: "Ana"), "Ana just filmed a clip")
    }

    func testNotificationRouteParsesCloudKitPayload() {
        let id = UUID()
        let route = NotificationRecordRoute(userInfo: [
            NotificationConstants.challengeIDKey: id.uuidString,
            NotificationConstants.dayKey: NSNumber(value: 4),
        ])

        XCTAssertEqual(route, NotificationRecordRoute(challengeID: id, day: 4))
    }

    // MARK: Room pushes

    func testRegistrationCarriesTheAppsOwnCopyForEveryKind() {
        UserDefaults.standard.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        defer { UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey) }
        let registration = SharedActivityNotificationService.registration(
            token: "ab", rooms: ["ZZZZZZ": "Other", "ABCDEF": "Our Week"],
            showNames: true, topic: "com.cassie.AISetlog", sandbox: false)

        XCTAssertEqual(registration.rooms.map(\.code), ["ABCDEF", "ZZZZZZ"])
        XCTAssertEqual(registration.rooms.first?.title, "Our Week")
        XCTAssertEqual(registration.alerts["comment"],
                       .init(format: "%1$@: %2$@", args: ["authorName", "text"]))
        XCTAssertEqual(Set(registration.alerts.keys), ["clip", "comment", "reaction", "poke"])
    }

    func testHiddenNamesLeaveTheAuthorOutOfTheAlert() {
        for kind in SharedActivityNotificationService.ActivityKind.allCases {
            let copy = SharedActivityNotificationService.alertCopy(kind: kind, showNames: false)
            XCTAssertFalse(copy.args.contains("authorName"), "\(kind)")
            let placeholders = copy.format.components(separatedBy: "$@").count - 1
            XCTAssertEqual(placeholders, copy.args.count, "\(kind)")
        }
    }

    func testRoomPushPayloadIsRecognised() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Room"]],
            "oneday": ["roomCode": "ABCDEF", "kind": "comment", "day": NSNumber(value: 3)],
        ]
        XCTAssertEqual(
            SharedActivityNotificationService.context(forRemote: userInfo),
            .init(roomCode: "ABCDEF", kind: .comment, day: 3))
        XCTAssertEqual(SharedActivityNotificationService.roomCode(forRemote: userInfo), "ABCDEF")
        XCTAssertNil(SharedActivityNotificationService.context(forRemote: ["aps": [:]]))
    }

    func testTappingARoomAlertOpensItsRoom() throws {
        let now = try date(2026, 7, 25, 12, 0)
        let room = makeChallenge(
            title: "Together", startDate: now, mode: .sevenDay, cardCount: 7, roomCode: "ABCDEF")
        let other = makeChallenge(
            title: "Other", startDate: now, mode: .sevenDay, cardCount: 7, roomCode: "ZZZZZZ")

        XCTAssertEqual(
            SharedActivityNotificationService.route(roomCode: "ABCDEF", day: nil, challenges: [other, room]),
            NotificationRecordRoute(challengeID: room.id, day: 1))
        XCTAssertEqual(
            SharedActivityNotificationService.route(roomCode: "ABCDEF", day: 4, challenges: [room]),
            NotificationRecordRoute(challengeID: room.id, day: 4))
        XCTAssertNil(SharedActivityNotificationService.route(roomCode: "ABCDEF", day: 4, challenges: [other]))
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
