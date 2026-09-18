import Foundation

/// Which rooms have already been offered "now send the code out".
///
/// A room is created empty, by design — you make it, then you invite. The gap
/// between those two is where rooms died: the composer closed, the story page
/// opened, and the one thing that had to happen next (getting the code to
/// somebody) was a capsule in the header competing with a list of moments to
/// film. Nothing was broken and nothing was wrong; there was simply no moment
/// that said *now*. `docs/ux-audit-2026-09-09.md` 3.1.
///
/// So the page offers it once, the first time you land on a room you own that
/// nobody else has joined. Once, per room, ever — recorded here rather than in
/// `@State`, because the story page is rebuilt every time you navigate back to
/// it and a nudge that returns on the fourth visit is nagging.
///
/// Keyed by room code rather than challenge id: the code is what the invitation
/// contains, and it is stable across the store being rebuilt.
enum RoomShareNudge {
    private static let key = "room.shareNudge.offered"

    private static var offered: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    /// Whether this room still deserves the nudge.
    ///
    /// - Parameter isEmptyRoom: true when nobody but the owner is in it. A room
    ///   a friend has already joined has had its invitation delivered — saying
    ///   "send the code out" over the top of that is the app not watching.
    static func shouldOffer(code: String, isEmptyRoom: Bool) -> Bool {
        isEmptyRoom && !offered.contains(code)
    }

    /// Called whether the share sheet was used or waved away. Declining is an
    /// answer, and asking again because the answer was "not now" is the thing
    /// this type exists to prevent.
    static func markOffered(code: String) {
        var codes = offered
        codes.insert(code)
        UserDefaults.standard.set(Array(codes), forKey: key)
    }

    /// Test seam. Nothing in the app calls this.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
