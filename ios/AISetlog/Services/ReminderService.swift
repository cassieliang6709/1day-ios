import Foundation
import UserNotifications

/// Reconciles the complete set of on-device evening capture reminders.
enum ReminderService {
    struct PlannedReminder: Equatable {
        let challengeID: UUID
        let day: Int
        let fireDate: Date
        let title: String
        let body: String
    }

    private struct Candidate {
        let plan: PlannedReminder
        let isShared: Bool
        let endDate: Date
        let progress: Double
    }

    private static let scheduler = ReminderScheduler()
    private static let prefix = "reminder."

    static func reconcile(for challenges: [Challenge]) {
        Task {
            await scheduler.reconcile(challenges: challenges)
        }
    }

    static func snooze(_ original: UNNotificationContent) {
        Task {
            await scheduler.snooze(original)
        }
    }

    static func plannedReminders(
        for challenges: [Challenge],
        now: Date = .now,
        calendar: Calendar = .current,
        hour: Int = NotificationPreferences.eveningHour,
        minute: Int = NotificationPreferences.eveningMinute
    ) -> [PlannedReminder] {
        var winnerByDay: [Date: Candidate] = [:]

        for challenge in challenges where !challenge.isComplete {
            let unrecorded = challenge.cards.filter { $0.clipFileName == nil }
            guard !unrecorded.isEmpty else { continue }
            let finalOffset = max(challenge.cards.count - 1, 0)
            let endDate = calendar.date(
                byAdding: .day,
                value: finalOffset,
                to: calendar.startOfDay(for: challenge.startDate)) ?? challenge.startDate
            let progress = Double(challenge.recordedCount)
                / Double(max(challenge.cards.count, 1))

            if challenge.isOneDay {
                guard let card = unrecorded.first,
                      let fireDate = fireDate(
                        on: challenge.startDate,
                        hour: hour,
                        minute: minute,
                        calendar: calendar),
                      fireDate > now
                else { continue }
                let candidate = Candidate(
                    plan: PlannedReminder(
                        challengeID: challenge.id,
                        day: card.day,
                        fireDate: fireDate,
                        title: challenge.title,
                        body: Strings.eveningOneDayReminder(remaining: unrecorded.count)),
                    isShared: challenge.isShared,
                    endDate: endDate,
                    progress: progress)
                keepPreferred(candidate, in: &winnerByDay, calendar: calendar)
                continue
            }

            for card in unrecorded {
                guard let date = calendar.date(
                    byAdding: .day,
                    value: card.day - 1,
                    to: calendar.startOfDay(for: challenge.startDate)),
                      let fireDate = fireDate(
                        on: date,
                        hour: hour,
                        minute: minute,
                        calendar: calendar),
                      fireDate > now
                else { continue }
                let prompt = challenge.momentValue(forSlot: card.day)
                let body = prompt.map {
                    Strings.reminderBodyWithPrompt(card.day, $0)
                } ?? Strings.reminderBody(card.day)
                let candidate = Candidate(
                    plan: PlannedReminder(
                        challengeID: challenge.id,
                        day: card.day,
                        fireDate: fireDate,
                        title: challenge.title,
                        body: body),
                    isShared: challenge.isShared,
                    endDate: endDate,
                    progress: progress)
                keepPreferred(candidate, in: &winnerByDay, calendar: calendar)
            }
        }

        return winnerByDay.values.map(\.plan).sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.challengeID.uuidString < $1.challengeID.uuidString
        }
    }

    private static func fireDate(
        on date: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        calendar.date(
            bySettingHour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59),
            second: 0,
            of: date)
    }

    private static func keepPreferred(
        _ candidate: Candidate,
        in winners: inout [Date: Candidate],
        calendar: Calendar
    ) {
        let day = calendar.startOfDay(for: candidate.plan.fireDate)
        guard let current = winners[day] else {
            winners[day] = candidate
            return
        }
        if isPreferred(candidate, over: current) {
            winners[day] = candidate
        }
    }

    private static func isPreferred(_ lhs: Candidate, over rhs: Candidate) -> Bool {
        if lhs.isShared != rhs.isShared { return lhs.isShared }
        if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
        if lhs.progress != rhs.progress { return lhs.progress > rhs.progress }
        return lhs.plan.challengeID.uuidString < rhs.plan.challengeID.uuidString
    }

    private actor ReminderScheduler {
        private let center = UNUserNotificationCenter.current()

        func reconcile(challenges: [Challenge]) async {
            await removeScheduledReminders()
            guard NotificationPreferences.eveningEnabled else { return }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                    || settings.authorizationStatus == .ephemeral
            else { return }

            let plans = ReminderService.plannedReminders(for: challenges).prefix(30)
            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default
                content.categoryIdentifier = NotificationConstants.eveningCategory
                content.userInfo = [
                    NotificationConstants.challengeIDKey: plan.challengeID.uuidString,
                    NotificationConstants.dayKey: plan.day,
                ]
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: plan.fireDate)
                let request = UNNotificationRequest(
                    identifier: "\(prefix)\(plan.challengeID.uuidString).\(plan.day)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: components,
                        repeats: false))
                try? await center.add(request)
            }
        }

        func snooze(_ original: UNNotificationContent) async {
            guard let content = original.mutableCopy()
                    as? UNMutableNotificationContent
            else { return }
            content.categoryIdentifier = NotificationConstants.eveningCategory
            let request = UNNotificationRequest(
                identifier: "\(prefix)snooze.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: 60 * 60,
                    repeats: false))
            try? await center.add(request)
        }

        private func removeScheduledReminders() async {
            let requests = await center.pendingNotificationRequests()
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
