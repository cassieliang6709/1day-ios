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

    /// Which moments have something in them. Kept so the card can point at the
    /// next open one rather than at the next one *I* haven't done.
    private let filledDays: Set<Int>

    /// The author id the composer writes for a story that was never shared.
    static let soloAuthorID = "local"

    init(momentCount: Int, clips: [DayClip], myID: String) {
        total = max(momentCount, 0)
        clipCount = clips.count
        // Days outside the story are dropped rather than clamped. Counting
        // them would let a room read "2/2, watch your film" while both real
        // moments sat empty — a number that is wrong rather than merely stale.
        let story = 1...max(momentCount, 1)
        let inStory = { (day: Int) in momentCount > 0 && story.contains(day) }
        let days = Set(clips.map(\.day).filter(inStory))
        filledDays = days
        filled = days.count
        mine = Set(
            clips
                .filter { $0.authorID == myID || $0.authorID == Self.soloAuthorID }
                .map(\.day)
                .filter(inStory)
        ).count
    }

    /// True when the room holds work from somebody other than me — the only
    /// case where "3/5" and "you 1" say different things.
    var hasOthers: Bool { filled > mine }

    /// Every moment has something in it. Not the same as *my* card being full:
    /// in a room, the day finishes when the day finishes.
    var isComplete: Bool { total > 0 && filled >= total }

    /// The moment to offer next — the first one nobody has filmed.
    ///
    /// Sending someone to a moment a friend already covered is the visible half
    /// of the same bug: the room says "Next: Morning light" while Morning light
    /// is on screen above it and Wind down is the empty slot.
    ///
    /// - Returns: a slot number, or the last one when the day is full — there
    ///   is always somewhere to point, and re-filming a moment is allowed.
    var nextOpenMoment: Int {
        guard total > 0 else { return 1 }
        return (1...total).first { !filledDays.contains($0) } ?? total
    }

    /// The slot the home card's button should open.
    ///
    /// Today's, when today is still empty. In a seven-day story the slots *are*
    /// days, and `nextOpenMoment` — the earliest empty one — sent somebody who
    /// missed Tuesday straight back to Tuesday on Thursday. The day you can
    /// still film is today; a missed day is caught up from the story page,
    /// where all of them are listed.
    ///
    /// - Parameter today: which slot is today, or `nil` for a one-day story
    ///   where every slot is today and "earliest empty" is the right answer.
    func slotToOffer(today: Int?) -> Int {
        guard total > 0 else { return 1 }
        guard let today else { return nextOpenMoment }
        let clamped = min(max(today, 1), total)
        // Only when it's still empty: a button that re-films the moment you
        // already have today is a button that does nothing new.
        return filledDays.contains(clamped) ? nextOpenMoment : clamped
    }

    /// Whether the slot on offer is today's, so the label can say
    /// "catch up day 2" instead of implying it is today's.
    func offeringToday(today: Int?) -> Bool {
        guard let today, total > 0 else { return true }
        return slotToOffer(today: today) == min(max(today, 1), total)
    }
}
