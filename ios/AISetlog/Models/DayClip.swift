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
    var recordedAt: Date?
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
        recordedAt: Date? = nil,
        emoji: [String] = [],
        comments: [String] = [],
        key: String? = nil
    ) {
        self.day = day
        self.url = url
        self.authorName = authorName
        self.authorID = authorID
        self.label = label
        self.overlayText = overlayText
        self.recordedAt = recordedAt
        self.emoji = emoji
        self.comments = comments
        self.id = key ?? "day\(day)"
    }
}
