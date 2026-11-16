#if DEBUG
import Foundation

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
