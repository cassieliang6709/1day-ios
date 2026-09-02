import Foundation

/// What the story page should offer next, and how it files everything else.
///
/// The page used to lay every moment out as an equally weighted tile, so seven
/// things asked to be tapped and none of them was the answer to "what now".
/// A day only ever has one next thing in it: the first moment nobody has
/// filmed, or — once every moment exists — the film. Everything else is either
/// something that happened or something that hasn't, and both of those are
/// lists rather than buttons.
struct StoryAgenda: Equatable {
    /// The single call to action the page is built around.
    enum Next: Equatable {
        /// Film this slot next.
        case film(slot: Int)
        /// Every moment holds footage. The only thing left to do is watch it.
        case watchTheFilm
    }

    /// Moments in the story.
    let total: Int
    /// Slots holding footage from anybody, in day order — the story so far.
    let filmed: [Int]
    /// Slots I could still film, in day order.
    ///
    /// A moment a friend filmed and I haven't stays in here. The grid used to
    /// swallow those slots whole — the tile turned into their take and there
    /// was no way left to add mine.
    let openToMe: [Int]
    let next: Next

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

        if let open = slots.first(where: { !anyones.contains($0) }) {
            next = .film(slot: open)
        } else if total > 0 {
            next = .watchTheFilm
        } else {
            // A story with no moments in it yet still has to point somewhere.
            next = .film(slot: 1)
        }
    }

    var filmedCount: Int { filmed.count }

    /// Every moment has something in it. Not the same as *my* card being full:
    /// in a room, the day finishes when the day finishes.
    var isComplete: Bool { total > 0 && filmed.count >= total }

    /// Open slots other than the one the card is already offering, so the
    /// quiet list never repeats the loud thing above it.
    var later: [Int] {
        guard case .film(let slot) = next else { return openToMe }
        return openToMe.filter { $0 != slot }
    }

    /// Whether a filmed slot is somebody else's take rather than mine — the
    /// thumbnail says so, and the slot also stays in the quiet list.
    func isAwaitingMine(slot: Int) -> Bool {
        filmed.contains(slot) && openToMe.contains(slot)
    }
}
