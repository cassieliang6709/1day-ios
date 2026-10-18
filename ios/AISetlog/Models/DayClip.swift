import Foundation

/// A recorded clip labeled with its challenge day — the stitcher's input.
/// In a shared room a single day can hold several clips (one per friend), so
/// `id` is unique rather than the day number.
struct DayClip: Identifiable {
    let id: String
    let day: Int
    let url: URL
    var authorName: String?
    var authorID: String?
    var label: String?
    var overlayText: String?
    /// Where `overlayText` sits on the frame, and how it's drawn. Nil draws it
    /// at `CaptionSticker.default`, which is where every caption used to go.
    var captionSticker: CaptionSticker?
    var recordedAt: Date?
    /// Which take of this person's moment this is. Nil is take 1 — the card's
    /// own fields, and the only take a clip from before takes existed has.
    var takeID: UUID?
    /// Emoji to float onto this clip in the final film (from its reactions).
    var emoji: [String]
    /// "name: text" comments to bubble up in the final film.
    var comments: [String]

    init(
        day: Int,
        url: URL,
        authorName: String? = nil,
        authorID: String? = nil,
        label: String? = nil,
        overlayText: String? = nil,
        captionSticker: CaptionSticker? = nil,
        recordedAt: Date? = nil,
        emoji: [String] = [],
        comments: [String] = [],
        key: String? = nil,
        takeID: UUID? = nil
    ) {
        self.day = day
        self.url = url
        self.authorName = authorName
        self.authorID = authorID
        self.label = label
        self.overlayText = overlayText
        self.captionSticker = captionSticker
        self.recordedAt = recordedAt
        self.emoji = emoji
        self.comments = comments
        self.takeID = takeID
        self.id = key ?? "day\(day)"
    }

    /// The same clip, read from somewhere else. For handing a processed copy of
    /// the footage onward without the rest of the app noticing: the `id` is
    /// carried over, so this is still that moment by that person and not a new
    /// one that happens to look the same.
    func replacingURL(_ url: URL) -> DayClip {
        DayClip(
            day: day, url: url, authorName: authorName, authorID: authorID,
            label: label, overlayText: overlayText, captionSticker: captionSticker,
            recordedAt: recordedAt,
            emoji: emoji, comments: comments, key: id, takeID: takeID)
    }
}
