import Foundation
import UserNotifications

/// Daily local reminders that pull a 7-day challenger back for Day 2..7.
/// Purely on-device: no server, no push entitlement — just UNUserNotificationCenter.
enum ReminderService {

    private static var center: UNUserNotificationCenter { .current() }
    private static let prefix = "reminder."

    /// Ask once; if granted, schedule one reminder per remaining day at 7pm,
    /// titled with that day's prompt ("Day 3 · The wall").
    static func scheduleReminders(for challenge: Challenge) {
        guard challenge.resolvedMode == .sevenDay, !challenge.isComplete else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let cal = Calendar.current
            let total = challenge.cards.count
            for day in 2...total {
                guard let date = cal.date(byAdding: .day, value: day - 1, to: cal.startOfDay(for: challenge.startDate)),
                      date > .now
                else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: date)
                comps.hour = 19
                comps.minute = 0

                let content = UNMutableNotificationContent()
                content.title = challenge.title
                content.body = ReminderService.body(day: day, challenge: challenge)
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "\(prefix)\(challenge.id.uuidString).\(day)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                center.add(request)
            }
        }
    }

    /// Drop every pending reminder for a challenge (deleted or completed).
    static func cancelReminders(for challengeID: UUID) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier)
                .filter { $0.hasPrefix("\(prefix)\(challengeID.uuidString).") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private static func body(day: Int, challenge: Challenge) -> String {
        if let key = challenge.momentValue(forSlot: day) {
            let prompt = MomentCatalog.localize(key)
            return Strings.reminderBodyWithPrompt(day, prompt)
        }
        return Strings.reminderBody(day)
    }
}
