import CloudKit
import Foundation
import UIKit
import UserNotifications

enum SharedActivityNotificationService {
    private static let subscriptionManager = SharedSubscriptionManager()
    private static let subscriptionPrefix = "roomActivity."
    private static let notificationPrefix = "roomActivityNotification."
    private static let throttlePrefix = "notifications.shared.lastActivity."
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private enum ActivityKind: String, CaseIterable {
        case clip
        case comment
        case reaction

        var recordType: String {
            switch self {
            case .clip: "Clip"
            case .comment: "Comment"
            case .reaction: "Reaction"
            }
        }

        var options: CKQuerySubscription.Options {
            switch self {
            case .clip: [.firesOnRecordCreation, .firesOnRecordUpdate]
            case .comment, .reaction: [.firesOnRecordCreation]
            }
        }
    }

    private struct SubscriptionContext {
        let roomCode: String
        let kind: ActivityKind
    }

    static func reconcileSubscriptions(for challenges: [Challenge]) {
        guard !isRunningTests, NotificationPreferences.sharedEnabled else { return }
        let roomCodes = Set(challenges.compactMap(\.roomCode))
        Task {
            await subscriptionManager.reconcile(roomCodes: roomCodes)
        }
    }

    static func removeSubscriptions() {
        guard !isRunningTests else { return }
        Task {
            await subscriptionManager.reconcile(roomCodes: [])
        }
    }

    static func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard NotificationPreferences.sharedEnabled,
              let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let query = notification as? CKQueryNotification,
              let subscriptionID = query.subscriptionID,
              let context = context(for: subscriptionID),
              !NotificationPreferences.isRoomMuted(context.roomCode),
              let challenge = persistedChallenges().first(where: {
                  $0.roomCode == context.roomCode
              })
        else { return .noData }

        let fields = await activityFields(from: query)
        let authorID = fields.authorID
        if !authorID.isEmpty, authorID == AccountStore.persistedUserID {
            return .noData
        }

        let now = Date.now
        let throttleKey = throttlePrefix + context.roomCode
        if let last = UserDefaults.standard.object(forKey: throttleKey) as? Date,
           now.timeIntervalSince(last) < 5 * 60 {
            return .noData
        }

        let content = UNMutableNotificationContent()
        content.title = challenge.title
        content.body = activityBody(
            kind: context.kind,
            authorName: fields.authorName,
            day: fields.day)
        content.sound = .default
        content.categoryIdentifier = NotificationConstants.activityCategory
        content.threadIdentifier = context.roomCode
        content.userInfo = [
            NotificationConstants.challengeIDKey: challenge.id.uuidString,
            NotificationConstants.dayKey: max(fields.day, 1),
        ]

        let identifier = notificationPrefix + context.roomCode
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        do {
            try await center.add(request)
            UserDefaults.standard.set(now, forKey: throttleKey)
            return .newData
        } catch {
            return .failed
        }
    }

    private static func context(for subscriptionID: String) -> SubscriptionContext? {
        guard subscriptionID.hasPrefix(subscriptionPrefix) else { return nil }
        let parts = subscriptionID.dropFirst(subscriptionPrefix.count).split(separator: ".")
        guard parts.count == 2, let kind = ActivityKind(rawValue: String(parts[1])) else {
            return nil
        }
        return SubscriptionContext(roomCode: String(parts[0]), kind: kind)
    }

    private static func activityFields(
        from notification: CKQueryNotification
    ) async -> (authorID: String, authorName: String, day: Int) {
        var authorID = notification.recordFields?["authorID"] as? String ?? ""
        var authorName = notification.recordFields?["authorName"] as? String ?? ""
        var day = notification.recordFields?["day"] as? Int ?? 1

        if (authorID.isEmpty || authorName.isEmpty), let recordID = notification.recordID {
            do {
                let record = try await CKContainer(identifier: CloudKitService.containerID)
                    .publicCloudDatabase.record(for: recordID)
                authorID = record["authorID"] as? String ?? authorID
                authorName = record["authorName"] as? String ?? authorName
                day = record["day"] as? Int ?? day
            } catch {
                // The desired keys normally arrive in the push. Generic copy is
                // still useful if CloudKit trims the payload or the record moved.
            }
        }
        return (authorID, authorName, max(day, 1))
    }

    private static func activityBody(
        kind: ActivityKind,
        authorName: String,
        day: Int
    ) -> String {
        let visibleName = NotificationPreferences.showFriendNames && !authorName.isEmpty
            ? authorName
            : nil
        switch kind {
        case .clip:
            return Strings.roomClipActivity(name: visibleName, day: day)
        case .comment:
            return Strings.roomCommentActivity(name: visibleName)
        case .reaction:
            return Strings.roomReactionActivity(name: visibleName)
        }
    }

    private static func persistedChallenges() -> [Challenge] {
        guard let data = UserDefaults.standard.data(
            forKey: UserDefaultsChallengeRepository.defaultsKey),
              let challenges = try? JSONDecoder().decode([Challenge].self, from: data)
        else { return [] }
        return challenges
    }

    private actor SharedSubscriptionManager {
        private var database: CKDatabase {
            CKContainer(identifier: CloudKitService.containerID).publicCloudDatabase
        }

        func reconcile(roomCodes: Set<String>) async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
            let desiredCodes = NotificationPreferences.sharedEnabled && allowed
                ? roomCodes.filter { !NotificationPreferences.isRoomMuted($0) }
                : []
            do {
                let existing = try await database.allSubscriptions()
                let existingIDs = Set(existing.map(\.subscriptionID))
                let desiredIDs = Set(desiredCodes.flatMap { code in
                    ActivityKind.allCases.map { subscriptionID(code: code, kind: $0) }
                })

                for id in existingIDs where id.hasPrefix(subscriptionPrefix) && !desiredIDs.contains(id) {
                    _ = try? await database.deleteSubscription(withID: id)
                }

                for code in desiredCodes {
                    for kind in ActivityKind.allCases {
                        let id = subscriptionID(code: code, kind: kind)
                        guard !existingIDs.contains(id) else { continue }
                        let subscription = CKQuerySubscription(
                            recordType: kind.recordType,
                            predicate: NSPredicate(format: "roomCode == %@", code),
                            subscriptionID: id,
                            options: kind.options)
                        let info = CKSubscription.NotificationInfo()
                        info.shouldSendContentAvailable = true
                        info.desiredKeys = ["roomCode", "day", "authorID", "authorName"]
                        subscription.notificationInfo = info
                        do {
                            _ = try await database.save(subscription)
                        } catch {
                            print("[notifications] subscription failed: \(error)")
                        }
                    }
                }
            } catch {
                print("[notifications] subscription reconciliation failed: \(error)")
            }
        }

        private func subscriptionID(code: String, kind: ActivityKind) -> String {
            "\(subscriptionPrefix)\(code).\(kind.rawValue)"
        }
    }
}
