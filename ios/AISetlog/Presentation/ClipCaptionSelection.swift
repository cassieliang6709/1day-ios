import Foundation

/// A DayCard is the local author's card, not the displayed friend's card.
enum ClipCaptionSelection {
    static func text(isMine: Bool, hasLiveCard: Bool, liveText: String?, snapshotText: String?) -> String? {
        // nil on an existing own card means explicitly cleared, not unavailable.
        if isMine && hasLiveCard { return liveText }
        return snapshotText
    }
}

extension ClipCaptionSelection {
    /// The same rule for the whole list: my own live card wins on my own page,
    /// and an empty list there means I deleted them, not that it's unknown.
    static func captions(
        isMine: Bool, hasLiveCard: Bool, live: [Caption], snapshot: [Caption]
    ) -> [Caption] {
        if isMine && hasLiveCard { return live }
        return snapshot
    }
}
