import Foundation

/// Where a loose clip can go, and which slot it lands in.
///
/// Two screens ask this now — the camera's "file this to…" sheet and the
/// drafts list — and they have to agree, or a clip you couldn't file at the
/// time would become unfilable forever.
enum ClipFiling {
    /// Only stories shot the same way round can take this clip: a challenge
    /// never mixes portrait and landscape frames in one film.
    ///
    /// A story with no room left is not a candidate. It used to be, and filing
    /// into one overwrote whichever day the story happened to be on — a loose
    /// clip quietly destroying a clip that was already in the film. There is no
    /// version of "put this somewhere" that should mean "delete that".
    static func candidates(
        in challenges: [Challenge], orientation: Challenge.Orientation
    ) -> [Challenge] {
        challenges.filter {
            $0.resolvedOrientation == orientation && targetDay(in: $0) != nil
        }
    }

    /// The slot the clip fills: the first empty one, in order.
    ///
    /// - Returns: the day, or nil when every slot is taken. Nil is the caller's
    ///   cue to refuse — never to pick a day that already holds something.
    static func targetDay(in challenge: Challenge) -> Int? {
        challenge.cards.first(where: { $0.clipFileName == nil })?.day
    }

    /// Why `candidates` came back empty.
    ///
    /// Two different situations wear the same symptom, and the advice for them
    /// is opposite: one is fixed by making a story, the other by clearing room
    /// in a story that already exists. The drafts list used to state only the
    /// first as grey text and drop 归档 out of the menu, so the second case
    /// read as "no portrait story" to someone looking straight at three of
    /// them.
    enum Blocker: Equatable {
        /// Nothing is shot this way round yet.
        case noStoryWithThisFrame
        /// Stories match the frame, but every moment in all of them is filmed.
        case everyMatchingStoryIsFull
    }

    /// - Returns: nil when the clip *can* be filed — the caller should offer
    ///   the picker rather than an explanation.
    static func blocker(
        in challenges: [Challenge], orientation: Challenge.Orientation
    ) -> Blocker? {
        guard candidates(in: challenges, orientation: orientation).isEmpty else {
            return nil
        }
        return challenges.contains { $0.resolvedOrientation == orientation }
            ? .everyMatchingStoryIsFull
            : .noStoryWithThisFrame
    }
}
