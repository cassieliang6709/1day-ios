import Foundation

/// Who is in a shared room, and which of them has actually filmed something.
///
/// The story page could say how far the day had got without ever saying who
/// the day belonged to. The only place another person appeared was a card
/// under every moment reading "waiting for Leo" — one 120pt card per absent
/// friend per moment, so three friends across five moments spent most of the
/// screen on things that hadn't happened. Absence is worth one line; presence
/// is worth a row of faces.
///
/// People, not moments. `StoryAgenda` decides which slot comes next and none
/// of that changes with who filmed it, so the two live apart.
struct RoomCast: Equatable {
    struct Member: Equatable, Identifiable {
        let id: String
        let name: String
        /// Me. First in the roster, and the only face it rings.
        let isMe: Bool
        /// Holds at least one clip in this story.
        let hasFilmed: Bool
    }

    /// A sentence about some of the people in the room, with the faces that
    /// belong to it. One value rather than two, so a view can't end up drawing
    /// one line's faces beside another line's words.
    struct Note: Equatable {
        let names: [String]
        let text: String
    }

    /// Everyone in the room: me first, then by name. This is the roster's order.
    let members: [Member]

    /// How many people a line names before the rest turn into a count. Two
    /// names and a count fit on a 375pt line; three names don't, as soon as
    /// somebody is called 佳琪.
    static let namesPerLine = 2

    /// - Parameters:
    ///   - members: the room as the store sees it — the owner, everyone who has
    ///     uploaded, and me once I'm signed in.
    ///   - momentCount: moments in the story. Clips outside it don't count as
    ///     somebody having filmed, the same rule `RoomProgress` counts by.
    ///   - myName: what a room calls me. Nil until I've signed in and picked
    ///     one.
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
        // A clip filed before the story was shared is authored "local" and is
        // still mine — otherwise joining a room would make my own takes read
        // as nobody's.
        let iFilmed = footage.keys.contains(myID)
            || footage.keys.contains(RoomProgress.soloAuthorID)

        // Me first, and always. The store only lists me once I'm signed in, so
        // without this a room of two reports itself as a room of one and the
        // roster hollows out a friend while quietly leaving me off it. Both of
        // my author ids are claimed here so a clip filed as "local" can't come
        // back as a fourth person standing next to me.
        var known: Set<String> = [myID, RoomProgress.soloAuthorID]
        var roster = [(
            id: myID,
            name: members.first { $0.id == myID }?.name ?? myName ?? Strings.youLabel)]

        for member in members where known.insert(member.id).inserted {
            roster.append(member)
        }

        // Whoever's footage is in the room is in the room, however the roster
        // got here. The store builds it from the owner, the synced uploads and
        // my account, which leaves out the author of a clip that arrived
        // before its membership did — and a thumbnail badged with a face the
        // roster can't account for is worse than no badge at all.
        for (authorID, authorName) in footage where known.insert(authorID).inserted {
            roster.append((authorID, authorName ?? Strings.defaultMemberName))
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

    // MARK: - Who's here

    var me: Member? { members.first(where: \.isMe) }
    var others: [Member] { members.filter { !$0.isMe } }

    /// Somebody other than me is in this room. Every line below is worth
    /// drawing only when this is true: in a room of one, naming who filmed
    /// names me, and an app that labels your own diary with your own name has
    /// forgotten who is holding it.
    var hasCompany: Bool { !others.isEmpty }

    var iFilmed: Bool { me?.hasFilmed ?? false }
    var othersWhoFilmed: [Member] { others.filter(\.hasFilmed) }
    var othersYetToFilm: [Member] { others.filter { !$0.hasFilmed } }

    // MARK: - What the room says

    /// Every face in the roster, in roster order.
    var rosterNames: [String] { members.map(\.name) }

    /// Faces to hollow out. In a room "pending" means hasn't filmed — that's
    /// the only thing the roster tracks, and it's why the roster can answer
    /// "who's here" and "who's turned up" in one row.
    var namesYetToFilm: Set<String> {
        Set(members.filter { !$0.hasFilmed }.map(\.name))
    }

    var myName: String? { me?.name }

    /// "3 人在这个房间".
    var rosterLine: String { Strings.peopleInRoom(members.count) }

    /// Who has put something in the day. Nil in a room nobody else has joined:
    /// the sentence would be about me, and the progress bar above it already
    /// counts my moments.
    var filmedNote: Note? {
        guard hasCompany else { return nil }
        let (named, overflow) = spelled(othersWhoFilmed)
        return Note(
            names: othersWhoFilmed.map(\.name),
            text: Strings.roomWhoFilmed(named, overflow: overflow, mineToo: iFilmed))
    }

    /// One line naming who hasn't filmed yet — a person, not a moment. Which
    /// moment they eventually pick is theirs to choose, which is why this
    /// replaced a waiting row under every slot.
    ///
    /// Nil once everybody has something in the day: there is nobody to wait
    /// for, and a line saying so is a line about nothing.
    var waitingNote: Note? {
        guard hasCompany, !othersYetToFilm.isEmpty else { return nil }
        let (named, overflow) = spelled(othersYetToFilm)
        return Note(
            names: othersYetToFilm.map(\.name),
            text: Strings.roomWaitingOn(named, overflow: overflow))
    }

    /// Names for a line, capped, plus how many people got left unnamed.
    private func spelled(_ people: [Member]) -> (named: [String], overflow: Int) {
        let named = people.prefix(Self.namesPerLine).map(\.name)
        return (named, people.count - named.count)
    }
}
