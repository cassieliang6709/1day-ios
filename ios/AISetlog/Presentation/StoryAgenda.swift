import Foundation

/// How the story page files its moments: what happened, what's still open to
/// me, and — softly — which one I might start with.
///
/// The page once laid every moment out as an equally weighted tile, so seven
/// things asked to be tapped and none of them was the answer to "what now".
/// The fix went too far the other way: it lifted *one* moment onto a card that
/// owned the loudest pixels on the screen and called it "next up", which turns
/// a day you can film in any order into a queue you have to work through.
///
/// A 1-day story is not a queue. Breakfast, the walk, the thing at 11pm — you
/// film whichever one is actually happening. So this type publishes a *set* of
/// open moments, all equal, plus one optional `suggested` slot that exists to
/// answer "I don't know where to start" and nothing more. Nothing here can
/// lock a moment, and no view is expected to hide one.
struct StoryAgenda: Equatable {
    /// Moments in the story.
    let total: Int
    /// Slots holding footage from anybody, in day order — the story so far.
    let filmed: [Int]
    /// Slots I could still film, in day order. Every one of them is tappable
    /// right now; the order is a reading order, not a running order.
    ///
    /// A moment a friend filmed and I haven't stays in here. The grid used to
    /// swallow those slots whole — the tile turned into their take and there
    /// was no way left to add mine.
    let openToMe: [Int]
    /// Where to start if you'd rather not choose: the earliest moment nobody
    /// has filmed. A hint, never a gate — it is drawn inside the open list at
    /// the same size as its neighbours, and every other row does the same
    /// thing when tapped.
    ///
    /// Nil once every moment holds footage, because then there is nothing left
    /// to suggest and the page has a film to offer instead.
    let suggested: Int?

    /// - Parameter myID: `RoomProgress.soloAuthorID` for a story that was
    ///   never shared, where every clip is mine by definition.
    init(momentCount: Int, clips: [DayClip], myID: String) {
        total = max(momentCount, 0)
        // Days outside the story are dropped rather than clamped, the same way
        // `RoomProgress` drops them: a stray clip must not be able to report a
        // moment as filmed that the story doesn't have.
        let slots = total > 0 ? Array(1...total) : []
        let anyones = Set(clips.map(\.day))
        let mine = Set(
            clips
                .filter { $0.authorID == myID || $0.authorID == RoomProgress.soloAuthorID }
                .map(\.day))

        filmed = slots.filter(anyones.contains)
        openToMe = slots.filter { !mine.contains($0) }
        // The earliest hole rather than the earliest slot after the last
        // filmed one: in a room, an untouched moment is worth more to the film
        // than a fourth take of breakfast. It is still only a suggestion.
        suggested = slots.first { !anyones.contains($0) }
    }

    var filmedCount: Int { filmed.count }

    /// Every moment has something in it. Not the same as *my* card being full:
    /// in a room, the day finishes when the day finishes.
    var isComplete: Bool { total > 0 && filmed.count >= total }

    /// Whether a filmed slot is somebody else's take rather than mine — the
    /// thumbnail says so, and the slot also keeps its row in the open list.
    func isAwaitingMine(slot: Int) -> Bool {
        filmed.contains(slot) && openToMe.contains(slot)
    }

    /// The one row that gets a softer word than its neighbours. Never true for
    /// a slot somebody has already filmed, so a row can't be asked to say
    /// "start here" and "add yours" at once.
    func isSuggested(slot: Int) -> Bool { suggested == slot }
}
