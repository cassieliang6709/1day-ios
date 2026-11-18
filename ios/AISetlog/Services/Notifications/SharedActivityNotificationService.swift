import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let roomActivityArrived = Notification.Name("roomActivityArrived")
}

enum SharedActivityNotificationService {
    private static let registrar = DeviceRegistrar()
    static let deviceTokenKey = "notifications.shared.apnsToken"
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

    struct AlertCopy: Codable, Equatable {
        let format: String
        let args: [String]
    }

    struct RoomRegistration: Codable, Equatable {
        let code: String
        let title: String
    }

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


    static func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: deviceTokenKey)
        reconcileSavedRooms()
    }

    static func reconcileSavedRooms() {
        reconcileSubscriptions(for: persistedChallenges())
    }

    static func reconcileSubscriptions(for challenges: [Challenge]) {
        guard !isRunningTests else { return }
        let rooms = NotificationPreferences.sharedEnabled ? roomTitles(for: challenges) : [:]
        Task { await registrar.reconcile(rooms: rooms) }
    }

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

    static func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard let context = context(forRemote: userInfo) else { return .noData }
        postActivityArrived(roomCode: context.roomCode)
        return .newData
    }

    static func roomCode(forRemote userInfo: [AnyHashable: Any]) -> String? {
        context(forRemote: userInfo)?.roomCode
    }

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
