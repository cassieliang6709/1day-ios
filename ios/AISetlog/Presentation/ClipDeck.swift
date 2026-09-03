import Foundation

/// The order you watch a story in.
///
/// Two screens need this order and they have to agree on it: the review screen
/// swipes left and right through the deck, and the story page lays the same
/// clips out as tiles. If each sorted its own way, tapping the third tile would
/// open the fifth page.
///
/// A shared room is what makes the order a real question rather than a
/// formality. A moment there holds one clip per person, so the story is a table
/// — moment down, who across — and the deck is that table read row by row.
struct ClipDeck {
    /// Every clip in the story, in the order you'd watch them.
    let clips: [DayClip]

    private let myID: String
    private let storyMomentCount: Int

    /// - Parameters:
    ///   - momentCount: how many slots the story has, for "3 / 5". Widened to
    ///     cover the highest day actually present: a clip that outlives its
    ///     story should still be watchable, and "6 / 5" helps nobody.
    ///   - myID: the signed-in account id, or `RoomProgress.soloAuthorID` when
    ///     there isn't one.
    init(clips: [DayClip], momentCount: Int, myID: String) {
        self.myID = myID
        self.storyMomentCount = max(momentCount, clips.map(\.day).max() ?? 0)
        self.clips = clips.sorted {
            Self.sortKey($0, myID: myID) < Self.sortKey($1, myID: myID)
        }
    }

    /// Moment first, then me, then everyone else by name.
    ///
    /// The middle term is the point. The store hands clips over sorted by
    /// `(day, authorName)`, which puts my own take behind any friend whose name
    /// happens to sort earlier — so in a room with Ava in it, my moment opens
    /// second and my tile sits on the right. Whose day this is shouldn't depend
    /// on the alphabet.
    ///
    /// `id` closes the key so the order is total: two people can share a
    /// display name, and a deck that reorders itself between two reads would
    /// hand the pager a different page for the same tile.
    private static func sortKey(
        _ clip: DayClip, myID: String
    ) -> (Int, Int, String, String) {
        (clip.day, isMine(clip, myID: myID) ? 0 : 1, clip.authorName ?? "", clip.id)
    }

    /// Whether a clip is mine.
    ///
    /// A story that was never shared writes `soloAuthorID`, and clips saved
    /// before authorship existed write nothing at all — both are mine. Getting
    /// this wrong doesn't just misorder the deck: it decides whether the review
    /// screen offers to re-record, which is not something to offer for somebody
    /// else's clip.
    static func isMine(_ clip: DayClip, myID: String) -> Bool {
        guard let authorID = clip.authorID else { return true }
        return authorID == myID || authorID == RoomProgress.soloAuthorID
    }

    var count: Int { clips.count }
    var isEmpty: Bool { clips.isEmpty }

    func clip(at index: Int) -> DayClip? {
        clips.indices.contains(index) ? clips[index] : nil
    }

    func isMine(at index: Int) -> Bool {
        clip(at: index).map { Self.isMine($0, myID: myID) } ?? false
    }

    /// Where a tap on a tile lands.
    ///
    /// - Parameter authorID: nil, `soloAuthorID` and my own id all mean the
    ///   same thing — my take on that moment.
    func index(ofDay day: Int, authorID: String?) -> Int? {
        clips.firstIndex { clip in
            guard clip.day == day else { return false }
            guard let authorID,
                  authorID != RoomProgress.soloAuthorID,
                  authorID != myID
            else { return Self.isMine(clip, myID: myID) }
            return clip.authorID == authorID
        }
    }

    /// The pages whose players should exist: the one you're looking at and its
    /// two neighbours.
    ///
    /// Three people filming five moments is fifteen clips, and fifteen looping
    /// `AVPlayer`s is not something to ask a phone to hold at once.
    func liveIndices(around index: Int) -> Set<Int> {
        guard clips.indices.contains(index) else { return [] }
        return Set((index - 1)...(index + 1)).filter { clips.indices.contains($0) }
    }

    /// What the chip over the video says.
    struct Position: Equatable {
        /// 1-based slot in the story.
        let day: Int
        let momentCount: Int
        /// The moment's name. Nil for a story with no prompts, where the clip
        /// is identified by its time instead.
        let label: String?
        /// Whose clip this is — nil when it's mine. The chip over your own face
        /// doesn't need to tell you your own name.
        let authorName: String?
    }

    func position(at index: Int) -> Position? {
        guard let clip = clip(at: index) else { return nil }
        return Position(
            day: clip.day,
            momentCount: storyMomentCount,
            label: clip.label,
            authorName: Self.isMine(clip, myID: myID) ? nil : clip.authorName)
    }
}
