#if DEBUG
import Foundation

enum DebugDeepLink: Equatable {
    case surface(String)
    case story(UUID)
    case avatar
    case resetOnboarding
    case seedLibrary
    case sync
    case dumpState

    static let surfaceNames: Set<String> = ["plans", "friends", "compose", "camera"]

    init?(path: String) {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n"))
        guard let url = URL(string: "oneday://debug/" + trimmed) else { return nil }
        self.init(url)
    }

    init?(_ url: URL) {
        guard url.scheme == "oneday", url.host == "debug" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch (parts.first, parts.dropFirst().first) {
        case ("surface", let name?) where Self.surfaceNames.contains(name):
            self = .surface(name)
        case ("story", let raw?):
            guard let id = UUID(uuidString: raw) else { return nil }
            self = .story(id)
        case ("avatar", nil): self = .avatar
        case ("reset-onboarding", nil): self = .resetOnboarding
        case ("seed-library", nil): self = .seedLibrary
        case ("sync", nil): self = .sync
        case ("dump-state", nil): self = .dumpState
        default: return nil
        }
    }
}

@MainActor
enum DebugLinkInbox {
    static let name = "com.cassie.AISetlog.debug.link"

    static var file: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("debug-link.txt")
    }

    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in
                Task { @MainActor in DebugLinkInbox.drain() }
            },
            name as CFString, nil, .deliverImmediately)
        if FileManager.default.fileExists(atPath: file.path) { drain() }
    }

    private static func drain() {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            Log.debug.error("inbox: notified but no \(file.lastPathComponent, privacy: .public)")
            return
        }
        try? FileManager.default.removeItem(at: file)
        for line in text.split(whereSeparator: \.isNewline) {
            guard let link = DebugDeepLink(path: String(line)) else {
                Log.debug.error("inbox: unknown link \(String(line), privacy: .public)")
                continue
            }
            NotificationCenter.default.post(name: .debugLinkInbox, object: nil, userInfo: ["link": link])
        }
    }
}

extension Notification.Name {
    static let debugLinkInbox = Notification.Name("debugLinkInbox")

    static let debugDeepLink = Notification.Name("debugDeepLink")
}
#endif
