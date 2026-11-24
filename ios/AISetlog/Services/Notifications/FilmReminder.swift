import Foundation
import UserNotifications

enum FilmReminder {
    private static let prefix = "film-reminder."
    private static let daysAhead = 7
    private static let hour = 20

    static func refresh(filmedToday: Bool, now: Date = .now) {
        Task { await reschedule(filmedToday: filmedToday, now: now) }
    }

    private static func reschedule(filmedToday: Bool, now: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for offset in 0..<daysAhead {
            if offset == 0, filmedToday { continue }
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(
                    bySettingHour: hour, minute: 0, second: 0, of: day),
                  fire > now
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = Strings.filmReminderTitle
            content.body = Strings.filmReminderBody
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(
                identifier: "\(prefix)\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }
}
