import Foundation

/// A DayCard is the local author's card, not the displayed friend's card.
enum ClipCaptionSelection {
    static func text(isMine: Bool, hasLiveCard: Bool, liveText: String?, snapshotText: String?) -> String? {
        // nil on an existing own card means explicitly cleared, not unavailable.
        if isMine && hasLiveCard { return liveText }
        return snapshotText
    }
}
