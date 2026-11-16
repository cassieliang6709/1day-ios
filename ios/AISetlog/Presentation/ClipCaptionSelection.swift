import Foundation

enum ClipCaptionSelection {
    static func text(isMine: Bool, hasLiveCard: Bool, liveText: String?, snapshotText: String?) -> String? {
        if isMine && hasLiveCard { return liveText }
        return snapshotText
    }
}

extension ClipCaptionSelection {
    static func captions(
        isMine: Bool, hasLiveCard: Bool, live: [Caption], snapshot: [Caption]
    ) -> [Caption] {
        if isMine && hasLiveCard { return live }
        return snapshot
    }
}
