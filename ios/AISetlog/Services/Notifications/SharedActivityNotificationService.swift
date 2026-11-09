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

/// Room pushes. The Worker sends them through APNs the moment someone films,
/// writes, reacts or pokes; this phone only tells it which rooms to alert it
/// about and what the alert says (`PUT /push/device`).
///
/// The copy is still the app's: it goes up as a format plus which fields fill
/// it, the Worker sends it back as `loc-key`/`loc-args`, and iOS formats it
/// on the phone. Nobody is alerted about their own record; a poke reaches
/// only the person poked — both decided on the server.
enum SharedActivityNotificationService {
    private static let registrar = DeviceRegistrar()
    static let deviceTokenKey = "notifications.shared.apnsToken"
    /// Info.plist mirrors `aps-environment`, which the app can't read itself.
    static var isSandbox: Bool {
        Bundle.main.object(forInfoDictionaryKey: "OneDayAPNsEnvironment") as? String == "development"
    }
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    enum ActivityKind: String, CaseIterable, Codable {
        case clip
        case comment
        case reaction
        case poke
    }

    /// One kind's alert: the format and which fields fill its `%n$@`s.
    struct AlertCopy: Codable, Equatable {
        let format: String
        let args: [String]
    }

    struct RoomRegistration: Codable, Equatable {
        let code: String
        let title: String
    }

    /// Everything the Worker keeps for this phone. An empty `rooms` removes
    /// the phone: "off" has to mean no alerts, since an alert APNs shows
    /// can't check a setting here first.
    struct DeviceRegistration: Codable, Equatable {
        let token: String
        let topic: String
        let sandbox: Bool
        let alerts: [String: AlertCopy]
        let rooms: [RoomRegistration]
    }

    static func alertCopy(kind: ActivityKind, showNames: Bool) -> AlertCopy {
        switch kind {
        case .clip:
            return AlertCopy(format: Strings.roomClipAlertFormat(named: showNames),
                             args: showNames ? ["authorName"] : [])
        case .comment:
            return AlertCopy(format: Strings.roomMessageAlertFormat(named: showNames),
                             args: showNames ? ["authorName", "text"] : ["text"])
        case .reaction:
            return AlertCopy(format: Strings.roomReactionAlertFormat(named: showNames),
                             args: showNames ? ["authorName"] : [])
        case .poke:
            return AlertCopy(format: Strings.roomPokeAlertFormat(named: showNames),
                             args: showNames ? ["authorName"] : [])
        }
    }

    static func registration(
        token: String,
        rooms: [String: String],
        showNames: Bool = NotificationPreferences.showFriendNames,
        topic: String = Bundle.main.bundleIdentifier ?? "",
        sandbox: Bool = isSandbox
    ) -> DeviceRegistration {
        DeviceRegistration(
            token: token,
            topic: topic,
            sandbox: sandbox,
            alerts: Dictionary(uniqueKeysWithValues: ActivityKind.allCases.map {
                ($0.rawValue, alertCopy(kind: $0, showNames: showNames))
            }),
            rooms: rooms.sorted { $0.key < $1.key }.map { RoomRegistration(code: $0.key, title: $0.value) })
    }

    // MARK: Registering

    /// Called by the app delegate with APNs' token for this install.
    static func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: deviceTokenKey)
        reconcileSavedRooms()
    }

    /// Re-registers with the rooms saved on this phone — after a sign-in,
    /// when nothing else has the list to hand.
    static func reconcileSavedRooms() {
        reconcileSubscriptions(for: persistedChallenges())
    }

    static func reconcileSubscriptions(for challenges: [Challenge]) {
        guard !isRunningTests else { return }
        let rooms = NotificationPreferences.sharedEnabled ? roomTitles(for: challenges) : [:]
        Task { await registrar.reconcile(rooms: rooms) }
    }

    /// Sign-out: this phone stops getting the last person's room alerts. Takes
    /// the session explicitly because the keychain is about to lose it.
    static func removeSubscriptions(session: AuthService.Session?) {
        guard !isRunningTests,
              let session,
              let token = UserDefaults.standard.string(forKey: deviceTokenKey)
        else { return }
        Task {
            struct Body: Encodable { let token: String }
            var api = OneDayAPI.shared
            api.fixedSession = session
            _ = try? await api.send("DELETE", ["push", "device"], json: Body(token: token))
        }
    }

    // MARK: Receiving

    /// What a room push carries besides the alert (`oneday` in the payload).
    struct RemoteContext: Equatable {
        let roomCode: String
        let kind: ActivityKind?
        let day: Int
    }

    static func context(forRemote userInfo: [AnyHashable: Any]) -> RemoteContext? {
        guard let info = userInfo["oneday"] as? [String: Any],
              let code = info["roomCode"] as? String, !code.isEmpty
        else { return nil }
        let day = (info["day"] as? NSNumber)?.intValue ?? info["day"] as? Int ?? 1
        return RemoteContext(
            roomCode: code,
            kind: (info["kind"] as? String).flatMap(ActivityKind.init),
            day: max(day, 1))
    }

    /// APNs has already put the alert on screen; all that's left is telling
    /// an open room to refetch.
    static func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard let context = context(forRemote: userInfo) else { return .noData }
        postActivityArrived(roomCode: context.roomCode)
        return .newData
    }

    /// The room code of a room push, or nil for anything else.
    static func roomCode(forRemote userInfo: [AnyHashable: Any]) -> String? {
        context(forRemote: userInfo)?.roomCode
    }

    /// Where tapping a room alert should land.
    static func route(forRemote userInfo: [AnyHashable: Any]) -> NotificationRecordRoute? {
        guard let context = context(forRemote: userInfo) else { return nil }
        return route(roomCode: context.roomCode, day: context.day, challenges: persistedChallenges())
    }

    static func route(roomCode: String, day: Int?, challenges: [Challenge]) -> NotificationRecordRoute? {
        guard let challenge = challenges.first(where: { $0.roomCode == roomCode }) else { return nil }
        return NotificationRecordRoute(challengeID: challenge.id, day: max(day ?? 1, 1))
    }

    static func postActivityArrived(roomCode: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .roomActivityArrived, object: nil, userInfo: ["roomCode": roomCode])
        }
    }

    // MARK: Helpers

    private static func roomTitles(for challenges: [Challenge]) -> [String: String] {
        var titles: [String: String] = [:]
        for challenge in challenges {
            guard let code = challenge.roomCode else { continue }
            titles[code] = ChallengePresenter(challenge: challenge).displayTitle
        }
        return titles
    }

    private static func persistedChallenges() -> [Challenge] {
        guard let data = UserDefaults.standard.data(
            forKey: UserDefaultsChallengeRepository.defaultsKey),
              let challenges = try? JSONDecoder().decode([Challenge].self, from: data)
        else { return [] }
        return challenges
    }

    private actor DeviceRegistrar {
        /// What the Worker last accepted, so an unchanged list isn't sent on
        /// every foreground.
        private var lastSent: DeviceRegistration?

        func reconcile(rooms: [String: String]) async {
            guard let token = UserDefaults.standard.string(forKey: SharedActivityNotificationService.deviceTokenKey),
                  OneDayAPI.shared.isSignedIn
            else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let allowed = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
            let desired = allowed ? rooms.filter { !NotificationPreferences.isRoomMuted($0.key) } : [:]
            let registration = SharedActivityNotificationService.registration(token: token, rooms: desired)
            guard registration != lastSent else { return }
            do {
                try await OneDayAPI.shared.send("PUT", ["push", "device"], json: registration)
                lastSent = registration
            } catch {
                print("[notifications] device registration failed: \(error)")
            }
        }
    }
}
