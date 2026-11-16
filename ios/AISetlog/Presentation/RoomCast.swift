import Foundation

struct RoomCast: Equatable {
    struct Member: Equatable, Identifiable {
        let id: String
        let name: String
        let isMe: Bool
        let hasFilmed: Bool
    }

    struct Note: Equatable {
        let names: [String]
        let text: String
    }

    let members: [Member]

    static let namesPerLine = 2

    init(
        members: [(id: String, name: String)],
        clips: [DayClip],
        momentCount: Int,
        myID: String,
        myName: String?
    ) {
        var footage: [String: String?] = [:]
        for clip in clips
        where momentCount > 0 && (1...momentCount).contains(clip.day) {
            footage[clip.authorID ?? RoomProgress.soloAuthorID] = clip.authorName
        }
        let iFilmed = footage.keys.contains(myID)
            || footage.keys.contains(RoomProgress.soloAuthorID)

        var known: Set<String> = [myID, RoomProgress.soloAuthorID]
        var roster = [(
            id: myID,
            name: Self.firstNamed(members.first { $0.id == myID }?.name, myName)
                ?? Strings.youLabel)]

        for member in members where known.insert(member.id).inserted {
            roster.append(member)
        }

        for (authorID, authorName) in footage where known.insert(authorID).inserted {
            roster.append((authorID, authorName ?? ""))
        }

        self.members = roster
            .map { member in
                let isMe = member.id == myID
                return Member(
                    id: member.id,
                    name: member.name,
                    isMe: isMe,
                    hasFilmed: isMe ? iFilmed : footage.keys.contains(member.id))
            }
            .sorted { lhs, rhs in
                if lhs.isMe != rhs.isMe { return lhs.isMe }
                return lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name
            }
    }

    private static func firstNamed(_ candidates: String?...) -> String? {
        candidates.compactMap { $0 }.first { !$0.isEmpty }
    }


    var me: Member? { members.first(where: \.isMe) }
    var others: [Member] { members.filter { !$0.isMe } }

    var hasCompany: Bool { !others.isEmpty }

    var iFilmed: Bool { me?.hasFilmed ?? false }
    var othersWhoFilmed: [Member] { others.filter(\.hasFilmed) }
    var othersYetToFilm: [Member] { others.filter { !$0.hasFilmed } }


    var rosterNames: [String] { members.map(\.name) }

    var namesYetToFilm: Set<String> {
        Set(members.filter { !$0.hasFilmed }.map(\.name))
    }

    var myName: String? { me?.name }

    var rosterLine: String { Strings.peopleInRoom(members.count) }

    var filmedNote: Note? {
        guard hasCompany else { return nil }
        let (named, overflow) = spelled(othersWhoFilmed)
        return Note(
            names: othersWhoFilmed.map(\.name),
            text: Strings.roomWhoFilmed(named, overflow: overflow, mineToo: iFilmed))
    }

    var waitingNote: Note? {
        guard hasCompany, !othersYetToFilm.isEmpty else { return nil }
        let (named, overflow) = spelled(othersYetToFilm)
        return Note(
            names: othersYetToFilm.map(\.name),
            text: Strings.roomWaitingOn(named, overflow: overflow))
    }

    private func spelled(_ people: [Member]) -> (named: [String], overflow: Int) {
        let named = people.prefix(Self.namesPerLine).map(\.name)
        return (named, people.count - named.count)
    }
}
