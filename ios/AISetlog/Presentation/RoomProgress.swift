import Foundation

/// How far a story has got — counted over everyone in it, not just you.
///
/// A shared room used to report `challenge.recordedCount`, which is the number
/// of *my own* cards holding a file. So a room with three moments filmed by
/// two friends read "0/5" to the third person, and the film chip stayed hidden
/// beside a button offering to preview five clips. The screen was quietly
/// telling someone their friends' day hadn't happened.
///
/// Two numbers, because a room has two questions in it: how far is the day,
/// and how much of it is mine. Collapsing them into one is what caused this.
struct RoomProgress: Equatable {
    /// Moments in the story.
    let total: Int
    /// Moments with at least one clip in them, from anybody.
    let filled: Int
    /// Moments I filmed.
    let mine: Int
    /// Clips in total — several people can film the same moment, and the
    /// finished film plays all of them, so this is what runtime is made of.
    let clipCount: Int

    /// The author id the composer writes for a story that was never shared.
    static let soloAuthorID = "local"

    init(momentCount: Int, clips: [DayClip], myID: String) {
        total = max(momentCount, 0)
        clipCount = clips.count
        let days = Set(clips.map(\.day))
        filled = min(days.count, total)
        let myDays = Set(
            clips
                .filter { $0.authorID == myID || $0.authorID == Self.soloAuthorID }
                .map(\.day))
        mine = min(myDays.count, total)
    }

    /// True when the room holds work from somebody other than me — the only
    /// case where "3/5" and "you 1" say different things.
    var hasOthers: Bool { filled > mine }
}
