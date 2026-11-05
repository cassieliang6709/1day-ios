import CloudKit
import CryptoKit
import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    /// Posted on the main queue whenever a room's push reaches the running app,
    /// so an open room can refetch instead of waiting for the next foreground.
    /// `userInfo["roomCode"]` names the room. May arrive twice for one push
    /// (once from the remote-notification callback, once from `willPresent`).
    static let roomActivityArrived = Notification.Name("roomActivityArrived")
}

enum SharedActivityNotificationService {
    private static let subscriptionManager = SharedSubscriptionManager()
    static let subscriptionPrefix = "roomActivity."
    private static let notificationPrefix = "roomActivityNotification."
    private static let throttlePrefix = "notifications.shared.lastActivity."
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    enum ActivityKind: String, CaseIterable {
        case clip
        case comment
        case reaction
        case poke

        var recordType: String {
            switch self {
            case .clip: "Clip"
            case .comment: "Comment"
            case .reaction: "Reaction"
            case .poke: "Poke"
            }
        }

        var options: CKQuerySubscription.Options {
            switch self {
            case .clip: [.firesOnRecordCreation, .firesOnRecordUpdate]
            case .comment, .reaction, .poke: [.firesOnRecordCreation]
            }
        }

        /// Which records in the room alert this person. Nobody is alerted about
        /// their own record. A kind aimed at one member (a poke) would match on
        /// its target field here instead.
        func alertPredicate(code: String, userID: String) -> NSPredicate {
            switch self {
            case .poke: NSPredicate(format: "roomCode == %@ AND targetAuthorID == %@", code, userID)
            case .clip, .comment, .reaction:
                NSPredicate(format: "roomCode == %@ AND authorID != %@", code, userID)
            }
        }
    }

    /// How a subscription reaches the person.
    ///
    /// `.alert` is the normal case: APNs shows the banner itself, so it arrives
    /// whether or not iOS lets the app wake — force-quit, Low Power Mode and
    /// the background budget all used to swallow silent pushes. `.silent` is
    /// the old wake-the-app-and-post-locally path, kept only for when CloudKit
    /// rejects the `authorID != me` predicate (the field is not queryable in
    /// that environment) or nobody is signed in: an alert subscription without
    /// that filter would buzz the sender for their own message.
    enum Delivery: Equatable {
        case alert
        case silent
    }

    struct SubscriptionContext: Equatable {
        let roomCode: String
        let kind: ActivityKind
        let delivery: Delivery
    }

    static func reconcileSubscriptions(for challenges: [Challenge]) {
        guard !isRunningTests else { return }
        // A server-side alert can't consult a preference on this phone, so
        // "off" has to mean "no subscriptions", not "ignore what arrives".
        let rooms = NotificationPreferences.sharedEnabled ? roomTitles(for: challenges) : [:]
        Task {
            await subscriptionManager.reconcile(rooms: rooms, userID: AccountStore.persistedUserID)
        }
    }

    static func removeSubscriptions() {
        guard !isRunningTests else { return }
        Task {
            await subscriptionManager.reconcile(rooms: [:], userID: nil)
        }
    }

    static func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let query = notification as? CKQueryNotification,
              let subscriptionID = query.subscriptionID,
              let context = context(for: subscriptionID)
        else { return .noData }

        postActivityArrived(roomCode: context.roomCode)
        // APNs already put this one on screen. Posting a local copy as well is
        // what made every alert show up twice.
        guard context.delivery == .silent else { return .newData }

        guard NotificationPreferences.sharedEnabled,
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
        // A poke is for one person; everyone else in the room ignores it.
        let isPoke = context.kind == .poke
        if isPoke, fields.targetAuthorID != AccountStore.persistedUserID {
            return .noData
        }

        // A burst of clip uploads or reactions is one piece of news; a burst of
        // chat messages is a conversation, and each line has to reach the
        // person it was written to.
        let now = Date.now
        // Pokes skip the room's 5-minute activity throttle: they are already
        // capped at one per sender per day.
        let throttleKey = throttlePrefix + context.roomCode
        if !isPoke, context.kind != .comment,
           let last = UserDefaults.standard.object(forKey: throttleKey) as? Date,
           now.timeIntervalSince(last) < 5 * 60 {
            return .noData
        }

        let content = UNMutableNotificationContent()
        content.title = ChallengePresenter(challenge: challenge).displayTitle
        // `fields.day` still routes the tap (`dayKey` below); it just isn't
        // read out any more — see `Strings.roomClipActivity`.
        content.body = activityBody(
            kind: context.kind,
            authorName: fields.authorName)
        content.sound = .default
        content.categoryIdentifier = NotificationConstants.activityCategory
        content.threadIdentifier = context.roomCode
        content.userInfo = [
            NotificationConstants.challengeIDKey: challenge.id.uuidString,
            NotificationConstants.dayKey: max(fields.day, 1),
        ]

        // Messages each get their own request; replacing a pending one is only
        // right for the throttled kinds, where the newest says it all.
        let identifier = isPoke
            ? notificationPrefix + context.roomCode + ".poke." + authorID
            : context.kind == .comment
            ? notificationPrefix + context.roomCode + "." + (query.recordID?.recordName ?? UUID().uuidString)
            : notificationPrefix + context.roomCode
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        do {
            try await center.add(request)
            if !isPoke, context.kind != .comment {
                UserDefaults.standard.set(now, forKey: throttleKey)
            }
            return .newData
        } catch {
            return .failed
        }
    }

    /// The room code of a CloudKit room push, or nil for anything else.
    static func roomCode(forRemote userInfo: [AnyHashable: Any]) -> String? {
        guard let query = CKNotification(fromRemoteNotificationDictionary: userInfo)
                as? CKQueryNotification,
              let subscriptionID = query.subscriptionID
        else { return nil }
        return context(for: subscriptionID)?.roomCode
    }

    /// Where tapping an alert CloudKit delivered should land. Those payloads
    /// carry CloudKit's own keys, not the challenge ID a local notification
    /// is given, so the room is looked up from the subscription it came from.
    static func route(forRemote userInfo: [AnyHashable: Any]) -> NotificationRecordRoute? {
        guard let query = CKNotification(fromRemoteNotificationDictionary: userInfo)
                as? CKQueryNotification,
              let subscriptionID = query.subscriptionID
        else { return nil }
        return route(
            subscriptionID: subscriptionID,
            day: (query.recordFields?["day"] as? NSNumber)?.intValue,
            challenges: persistedChallenges())
    }

    static func route(
        subscriptionID: String,
        day: Int?,
        challenges: [Challenge]
    ) -> NotificationRecordRoute? {
        guard let context = context(for: subscriptionID),
              let challenge = challenges.first(where: { $0.roomCode == context.roomCode })
        else { return nil }
        return NotificationRecordRoute(challengeID: challenge.id, day: max(day ?? 1, 1))
    }

    static func postActivityArrived(roomCode: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .roomActivityArrived, object: nil, userInfo: ["roomCode": roomCode])
        }
    }

    // MARK: Subscription identity

    /// Accepts the three generations of ID:
    /// `roomActivity.<code>.<kind>` (pre-alert, silent),
    /// `roomActivity.v2s.<code>.<kind>` (silent fallback) and
    /// `roomActivity.v2.<code>.<kind>.<fingerprint>` (alert).
    static func context(for subscriptionID: String) -> SubscriptionContext? {
        guard subscriptionID.hasPrefix(subscriptionPrefix) else { return nil }
        let parts = subscriptionID.dropFirst(subscriptionPrefix.count)
            .split(separator: ".").map(String.init)
        switch (parts.count, parts.first) {
        case (2, _):
            guard let kind = ActivityKind(rawValue: parts[1]) else { return nil }
            return SubscriptionContext(roomCode: parts[0], kind: kind, delivery: .silent)
        case (3, "v2s"):
            guard let kind = ActivityKind(rawValue: parts[2]) else { return nil }
            return SubscriptionContext(roomCode: parts[1], kind: kind, delivery: .silent)
        case (4, "v2"):
            guard let kind = ActivityKind(rawValue: parts[2]) else { return nil }
            return SubscriptionContext(roomCode: parts[1], kind: kind, delivery: .alert)
        default:
            return nil
        }
    }

    static func silentSubscriptionID(code: String, kind: ActivityKind) -> String {
        "\(subscriptionPrefix)v2s.\(code).\(kind.rawValue)"
    }

    /// The alert subscription for one room and kind, built entirely here so
    /// the shape can be tested without a CloudKit account.
    ///
    /// Everything that is baked into the alert on the server — the room title,
    /// the copy's language, whether names show, whose records are filtered
    /// out — goes into the ID's fingerprint. Change any of them and the ID
    /// changes, so reconciliation replaces the subscription instead of leaving
    /// a stale one in place.
    static func alertSubscription(
        code: String,
        kind: ActivityKind,
        title: String,
        userID: String,
        showNames: Bool = NotificationPreferences.showFriendNames
    ) -> CKQuerySubscription {
        let info = CKSubscription.NotificationInfo()
        info.title = title
        let (format, args) = alertFormat(kind: kind, showNames: showNames)
        info.alertLocalizationKey = format
        info.alertLocalizationArgs = args.isEmpty ? nil : args
        info.soundName = "default"
        info.category = NotificationConstants.activityCategory
        // Kept so a running app hears about it and can refresh the room.
        info.shouldSendContentAvailable = true
        info.desiredKeys = ["roomCode", "day", "authorID", "authorName", "targetAuthorID"]
        // Several uploads or reactions stack into one entry per room. Messages
        // and pokes are left uncollapsed: each one is for someone.
        if kind == .clip || kind == .reaction { info.collapseIDKey = "roomCode" }

        let predicate = kind.alertPredicate(code: code, userID: userID)
        let fingerprintSource = [
            title, format, args.joined(separator: ","), predicate.predicateFormat,
            kind.options.rawValue.description,
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(fingerprintSource.utf8))
        let fingerprint = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        let subscription = CKQuerySubscription(
            recordType: kind.recordType,
            predicate: predicate,
            subscriptionID: "\(subscriptionPrefix)v2.\(code).\(kind.rawValue).\(fingerprint)",
            options: kind.options)
        subscription.notificationInfo = info
        return subscription
    }

    static func silentSubscription(code: String, kind: ActivityKind) -> CKQuerySubscription {
        let subscription = CKQuerySubscription(
            recordType: kind.recordType,
            predicate: NSPredicate(format: "roomCode == %@", code),
            subscriptionID: silentSubscriptionID(code: code, kind: kind),
            options: kind.options)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.desiredKeys = ["roomCode", "day", "authorID", "authorName", "targetAuthorID"]
        subscription.notificationInfo = info
        return subscription
    }

    private static func alertFormat(
        kind: ActivityKind,
        showNames: Bool
    ) -> (format: String, args: [String]) {
        switch kind {
        case .clip:
            return (Strings.roomClipAlertFormat(named: showNames),
                    showNames ? ["authorName"] : [])
        case .comment:
            return (Strings.roomMessageAlertFormat(named: showNames),
                    showNames ? ["authorName", "text"] : ["text"])
        case .reaction:
            return (Strings.roomReactionAlertFormat(named: showNames),
                    showNames ? ["authorName"] : [])
        case .poke:
            return (Strings.roomPokeAlertFormat(named: showNames),
                    showNames ? ["authorName"] : [])
        }
    }

    private static func roomTitles(for challenges: [Challenge]) -> [String: String] {
        var titles: [String: String] = [:]
        for challenge in challenges {
            guard let code = challenge.roomCode else { continue }
            titles[code] = ChallengePresenter(challenge: challenge).displayTitle
        }
        return titles
    }

    // MARK: Silent-path helpers

    private static func activityFields(
        from notification: CKQueryNotification
    ) async -> (authorID: String, authorName: String, day: Int, targetAuthorID: String) {
        var authorID = notification.recordFields?["authorID"] as? String ?? ""
        var authorName = notification.recordFields?["authorName"] as? String ?? ""
        var day = notification.recordFields?["day"] as? Int ?? 1
        var targetAuthorID = notification.recordFields?["targetAuthorID"] as? String ?? ""

        if (authorID.isEmpty || authorName.isEmpty), let recordID = notification.recordID {
            do {
                let record = try await CKContainer(identifier: CloudKitService.containerID)
                    .publicCloudDatabase.record(for: recordID)
                authorID = record["authorID"] as? String ?? authorID
                authorName = record["authorName"] as? String ?? authorName
                day = record["day"] as? Int ?? day
                targetAuthorID = record["targetAuthorID"] as? String ?? targetAuthorID
            } catch {
                // The desired keys normally arrive in the push. Generic copy is
                // still useful if CloudKit trims the payload or the record moved.
            }
        }
        return (authorID, authorName, max(day, 1), targetAuthorID)
    }

    private static func activityBody(
        kind: ActivityKind,
        authorName: String
    ) -> String {
        let visibleName = NotificationPreferences.showFriendNames && !authorName.isEmpty
            ? authorName
            : nil
        switch kind {
        case .clip:
            return Strings.roomClipActivity(name: visibleName)
        case .comment:
            return Strings.roomCommentActivity(name: visibleName)
        case .reaction:
            return Strings.roomReactionActivity(name: visibleName)
        case .poke:
            return Strings.roomPokeActivity(name: visibleName)
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
        /// Alert IDs CloudKit already turned down this launch. Retried on the
        /// next launch, so a schema that later makes `authorID` queryable
        /// upgrades the silent fallback without anyone doing anything.
        private var rejectedAlertIDs: Set<String> = []
        /// With notifications off, one sweep per launch is enough to remove
        /// what an earlier "on" left behind.
        private var sweptWhileEmpty = false

        func reconcile(rooms: [String: String], userID: String?) async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
            let desired = allowed
                ? rooms.filter { !NotificationPreferences.isRoomMuted($0.key) }
                : [:]
            if desired.isEmpty {
                guard !sweptWhileEmpty else { return }
                sweptWhileEmpty = true
            } else {
                sweptWhileEmpty = false
            }
            let me = userID.flatMap { $0.isEmpty ? nil : $0 }

            do {
                let existingIDs = Set(try await database.allSubscriptions().map(\.subscriptionID))
                var keep: Set<String> = []

                for (code, title) in desired {
                    for kind in ActivityKind.allCases {
                        let silentID = silentSubscriptionID(code: code, kind: kind)
                        guard let me else {
                            if await ensure(silentSubscription(code: code, kind: kind), existing: existingIDs) {
                                keep.insert(silentID)
                            }
                            continue
                        }
                        let alert = alertSubscription(code: code, kind: kind, title: title, userID: me)
                        let alertID = alert.subscriptionID
                        if existingIDs.contains(alertID) {
                            keep.insert(alertID)
                            continue
                        }
                        if !rejectedAlertIDs.contains(alertID) {
                            do {
                                _ = try await database.save(alert)
                                keep.insert(alertID)
                                continue
                            } catch let error as CKError
                                where error.code == .invalidArguments
                                    || error.code == .serverRejectedRequest {
                                print("[notifications] alert subscription rejected, using silent: \(error)")
                                rejectedAlertIDs.insert(alertID)
                            } catch {
                                // Network or account trouble: try again next
                                // reconcile, and keep whatever already works.
                                print("[notifications] subscription failed: \(error)")
                                keep.formUnion(existingIDs.filter {
                                    context(for: $0).map { $0.roomCode == code && $0.kind == kind } ?? false
                                })
                                continue
                            }
                        }
                        if await ensure(silentSubscription(code: code, kind: kind), existing: existingIDs) {
                            keep.insert(silentID)
                        }
                    }
                }

                // Deletes run after the saves so a room is never left without
                // a subscription while its replacement is being made.
                for id in existingIDs where id.hasPrefix(subscriptionPrefix) && !keep.contains(id) {
                    _ = try? await database.deleteSubscription(withID: id)
                }
            } catch {
                print("[notifications] subscription reconciliation failed: \(error)")
                if desired.isEmpty { sweptWhileEmpty = false }
            }
        }

        private func ensure(_ subscription: CKQuerySubscription, existing: Set<String>) async -> Bool {
            if existing.contains(subscription.subscriptionID) { return true }
            do {
                _ = try await database.save(subscription)
                return true
            } catch {
                print("[notifications] subscription failed: \(error)")
                return false
            }
        }
    }
}
