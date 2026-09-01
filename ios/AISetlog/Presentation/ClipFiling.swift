import Foundation

/// Where a loose clip can go, and which slot it lands in.
///
/// Two screens ask this now — the camera's "file this to…" sheet and the
/// drafts list — and they have to agree, or a clip you couldn't file at the
/// time would become unfilable forever.
enum ClipFiling {
    /// Only stories shot the same way round can take this clip: a challenge
    /// never mixes portrait and landscape frames in one film.
    static func candidates(
        in challenges: [Challenge], orientation: Challenge.Orientation
    ) -> [Challenge] {
        challenges.filter { $0.resolvedOrientation == orientation }
    }

    /// The slot the clip fills: the first empty one, in order.
    ///
    /// A full story has no empty slot, so the clip overwrites the day the
    /// story is currently on — clamped inside the story, since a seven-day
    /// challenge left alone for a fortnight is on "day 15".
    static func targetDay(
        in challenge: Challenge, now: Date = .now, calendar: Calendar = .current
    ) -> Int {
        if let open = challenge.cards.first(where: { $0.clipFileName == nil })?.day {
            return open
        }
        // Deliberately not `challenge.currentDay`: that reads the clock, and a
        // "which day is this" rule you can't test at a chosen date isn't one.
        let elapsed = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: challenge.startDate),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return min(max(elapsed + 1, 1), max(challenge.cards.count, 1))
    }
}
