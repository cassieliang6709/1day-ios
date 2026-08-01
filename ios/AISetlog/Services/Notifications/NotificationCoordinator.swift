import Foundation
import UIKit
import UserNotifications

struct NotificationRecordRoute: Codable, Equatable, Identifiable {
    let challengeID: UUID
    let day: Int
    var id: String { "\(challengeID.uuidString).\(day)" }

    init?(userInfo: [AnyHashable: Any]) {
        guard let rawID = userInfo[NotificationConstants.challengeIDKey] as? String,
              let challengeID = UUID(uuidString: rawID)
        else { return nil }
        let day = (userInfo[NotificationConstants.dayKey] as? NSNumber)?.intValue
            ?? userInfo[NotificationConstants.dayKey] as? Int
            ?? 1
        self.init(challengeID: challengeID, day: max(day, 1))
    }

    init(challengeID: UUID, day: Int) {
        self.challengeID = challengeID
        self.day = day
    }
}

extension Notification.Name {
    static let oneDayNotificationRoutePending = Notification.Name(
        "com.cassie.AISetlog.notificationRoutePending")
}

enum NotificationConstants {
    static let eveningCategory = "EVENING_REMINDER"
    static let activityCategory = "ROOM_ACTIVITY"
    static let recordAction = "RECORD_NOW"
    static let snoozeAction = "REMIND_IN_ONE_HOUR"
    static let challengeIDKey = "challengeID"
    static let dayKey = "day"
}

enum NotificationPreferences {
    static let eveningEnabledKey = "notifications.evening.enabled"
    static let eveningHourKey = "notifications.evening.hour"
    static let eveningMinuteKey = "notifications.evening.minute"
    static let primerSeenKey = "notifications.evening.primerSeen"
    static let sharedEnabledKey = "notifications.shared.enabled"
    static let showFriendNamesKey = "notifications.shared.showFriendNames"
    static let mutedRoomsKey = "notifications.shared.mutedRooms"

    private static var defaults: UserDefaults { .standard }

    /// Clears every stored preference. Part of account deletion — leaving a
    /// reminder schedule behind after someone erases their account would keep
    /// notifying a person who asked to be gone.
    static func resetAll() {
        for key in [
            eveningEnabledKey, eveningHourKey, eveningMinuteKey, primerSeenKey,
            sharedEnabledKey, showFriendNamesKey, mutedRoomsKey,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    static var eveningEnabled: Bool {
        get { defaults.bool(forKey: eveningEnabledKey) }
        set { defaults.set(newValue, forKey: eveningEnabledKey) }
    }

    static var eveningHour: Int {
        get { defaults.object(forKey: eveningHourKey) as? Int ?? 20 }
        set { defaults.set(min(max(newValue, 0), 23), forKey: eveningHourKey) }
    }

    static var eveningMinute: Int {
        get { defaults.object(forKey: eveningMinuteKey) as? Int ?? 30 }
        set { defaults.set(min(max(newValue, 0), 59), forKey: eveningMinuteKey) }
    }

    static var primerSeen: Bool {
        get { defaults.bool(forKey: primerSeenKey) }
        set { defaults.set(newValue, forKey: primerSeenKey) }
    }

    static var sharedEnabled: Bool {
        get { defaults.bool(forKey: sharedEnabledKey) }
        set { defaults.set(newValue, forKey: sharedEnabledKey) }
    }

    static var showFriendNames: Bool {
        get { defaults.bool(forKey: showFriendNamesKey) }
        set { defaults.set(newValue, forKey: showFriendNamesKey) }
    }

    static var mutedRoomCodes: Set<String> {
        get {
            guard let data = defaults.data(forKey: mutedRoomsKey),
                  let codes = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return Set(codes)
        }
        set {
            let codes = newValue.sorted()
            if let data = try? JSONEncoder().encode(codes) {
                defaults.set(data, forKey: mutedRoomsKey)
            }
        }
    }

    static func isRoomMuted(_ code: String) -> Bool {
        mutedRoomCodes.contains(code)
    }

    static func setRoom(_ code: String, muted: Bool) {
        var codes = mutedRoomCodes
        if muted { codes.insert(code) } else { codes.remove(code) }
        mutedRoomCodes = codes
    }
}

enum NotificationRouteInbox {
    private static let key = "notifications.pendingRecordRoute"

    static func enqueue(_ route: NotificationRecordRoute) {
        if let data = try? JSONEncoder().encode(route) {
            UserDefaults.standard.set(data, forKey: key)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .oneDayNotificationRoutePending, object: nil)
        }
    }

    static func consume() -> NotificationRecordRoute? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let route = try? JSONDecoder().decode(NotificationRecordRoute.self, from: data)
        else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return route
    }
}

enum NotificationPermissionService {
    static func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            return false
        }
    }

    static func registerForRemoteNotificationsIfNeeded() {
        guard NotificationPreferences.sharedEnabled else { return }
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}

final class NotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Self.registerCategories(on: center)
        NotificationPermissionService.registerForRemoteNotificationsIfNeeded()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == NotificationConstants.snoozeAction {
            ReminderService.snooze(response.notification.request.content)
        } else if response.actionIdentifier != UNNotificationDismissActionIdentifier,
                  let route = NotificationRecordRoute(
                    userInfo: response.notification.request.content.userInfo) {
            NotificationRouteInbox.enqueue(route)
        }
        completionHandler()
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            completionHandler(
                await SharedActivityNotificationService.handleRemoteNotification(userInfo))
        }
    }

    private static func registerCategories(on center: UNUserNotificationCenter) {
        let record = UNNotificationAction(
            identifier: NotificationConstants.recordAction,
            title: Strings.recordNow,
            options: [.foreground])
        let snooze = UNNotificationAction(
            identifier: NotificationConstants.snoozeAction,
            title: Strings.remindInOneHour)
        let evening = UNNotificationCategory(
            identifier: NotificationConstants.eveningCategory,
            actions: [record, snooze],
            intentIdentifiers: [])
        let activity = UNNotificationCategory(
            identifier: NotificationConstants.activityCategory,
            actions: [record],
            intentIdentifiers: [])
        center.setNotificationCategories([evening, activity])
    }
}
