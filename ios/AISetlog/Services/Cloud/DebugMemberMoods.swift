#if DEBUG
import Foundation

/// Debug-only: gives everyone who has footage in a room a mood for today, so
/// the room page's mood faces can be seen (and screenshotted) on a Simulator
/// that can't read real `Member` records. Off unless the app is launched with
/// `-debugMemberMoods YES`. Nothing is written anywhere.
@MainActor
enum DebugMemberMoods {
    static let flagKey = "debugMemberMoods"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: flagKey) }

    static func add(
        to members: inout [String: [String: CloudKitService.RemoteMember]],
        code: String, authors: [String]
    ) {
        guard isOn else { return }
        var room = members[code] ?? [:]
        for (i, id) in Array(Set(authors)).sorted().enumerated() where room[id]?.moodKind == nil {
            let mood = Mood.allCases[(i + 1) % Mood.allCases.count]
            room[id] = CloudKitService.RemoteMember(
                userID: id, displayName: room[id]?.displayName ?? "",
                avatarURL: room[id]?.avatarURL, moodKind: mood.rawValue, moodDay: .now)
        }
        members[code] = room
    }
}
#endif
