import Foundation

struct DayClip: Identifiable, Codable {
    let id: String
    let day: Int
    let url: URL
    var authorName: String?
    var authorID: String?
    var label: String?
    var captions: [Caption]
    var overlayText: String? {
        get { captions.firstText }
        set { captions.setFirstText(newValue) }
    }
    var captionSticker: CaptionSticker? {
        get { captions.first?.sticker }
        set { captions.setFirstSticker(newValue) }
    }
    var recordedAt: Date?
    var takeID: UUID?
    var emoji: [String]
    var comments: [String]

    init(
        day: Int,
        url: URL,
        authorName: String? = nil,
        authorID: String? = nil,
        label: String? = nil,
        overlayText: String? = nil,
        captionSticker: CaptionSticker? = nil,
        captions: [Caption]? = nil,
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
        self.captions = captions ?? .single(overlayText, sticker: captionSticker)
        self.recordedAt = recordedAt
        self.emoji = emoji
        self.comments = comments
        self.takeID = takeID
        self.id = key ?? "day\(day)"
    }

    func replacingURL(_ url: URL) -> DayClip {
        DayClip(
            day: day, url: url, authorName: authorName, authorID: authorID,
            label: label, captions: captions,
            recordedAt: recordedAt,
            emoji: emoji, comments: comments, key: id, takeID: takeID)
    }
}
