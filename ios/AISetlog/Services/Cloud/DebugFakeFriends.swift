#if DEBUG
import Foundation

/// Debug-only stand-ins for friends, so a real shared room on a single phone
/// shows both a live tile and a grey one (with 拍一拍). Off unless the app is
/// launched with `-debugFakeFriends YES`; nothing is uploaded — the clips are
/// appended to the local copy after every sync.
@MainActor
enum DebugFakeFriends {
    static let flagKey = "debugFakeFriends"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: flagKey) }

    private struct Friend {
        let id: String
        let name: String
        /// Days ago their takes were filmed. 0 = today.
        let daysAgo: [Int]
    }

    private static let friends = [
        Friend(id: "debug-friend-xiaohong", name: "小红", daysAgo: [0, 1]),
        Friend(id: "debug-friend-xiaoming", name: "小明", daysAgo: [3, 5]),
    ]

    /// Rendered files, made once per launch.
    private static var rendered: [String: URL] = [:]

    static func clips(for code: String, orientation: Challenge.Orientation = .portrait) async -> [CloudKitService.RemoteClip] {
        guard isOn else { return [] }
        var out: [CloudKitService.RemoteClip] = []
        for friend in friends {
            for (index, daysAgo) in friend.daysAgo.enumerated() {
                let day = index + 1
                let key = "\(friend.id)_\(day)"
                if rendered[key] == nil {
                    rendered[key] = await DemoClipFactory.makeClip(
                        moment: day, label: "假视频", author: friend.name,
                        seconds: 3, orientation: orientation)
                }
                guard let url = rendered[key] else { continue }
                let at = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
                    .addingTimeInterval(-Double(15 * 60 * (index + 1)))
                out.append(.init(
                    id: CloudKitService.clipRecordName(code: code, authorID: friend.id, day: day),
                    day: day, authorID: friend.id, authorName: friend.name,
                    recordedAt: at, localURL: url,
                    overlayText: daysAgo == 0 ? "今天的假视频" : nil))
            }
        }
        return out
    }
}
#endif
