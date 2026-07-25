import Foundation

struct DayCard: Codable, Identifiable {
    let day: Int
    var clipFileName: String?
    var recordedAt: Date?
    var overlayText: String?
    var reactions: [ClipReaction] = []
    var comments: [ClipComment] = []

    var id: Int { day }

    init(
        day: Int,
        clipFileName: String? = nil,
        recordedAt: Date? = nil,
        overlayText: String? = nil,
        reactions: [ClipReaction] = [],
        comments: [ClipComment] = []
    ) {
        self.day = day
        self.clipFileName = clipFileName
        self.recordedAt = recordedAt
        self.overlayText = overlayText
        self.reactions = reactions
        self.comments = comments
    }

    enum CodingKeys: String, CodingKey {
        case day, clipFileName, recordedAt, overlayText, reactions, comments
    }

    // Custom decode: synthesized Codable would throw on the reactions/comments
    // keys being absent in pre-existing saved challenges. Default them instead
    // so an app update never wipes someone's in-progress challenge.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(Int.self, forKey: .day)
        clipFileName = try c.decodeIfPresent(String.self, forKey: .clipFileName)
        recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt)
        overlayText = try c.decodeIfPresent(String.self, forKey: .overlayText)
        reactions = try c.decodeIfPresent([ClipReaction].self, forKey: .reactions) ?? []
        comments = try c.decodeIfPresent([ClipComment].self, forKey: .comments) ?? []
    }

    enum Status: Equatable {
        case done      // clip recorded
        case today     // it's this day, no clip yet
        case missed    // day passed without a clip (still recordable, late)
        case locked    // future day
    }

    func status(currentDay: Int) -> Status {
        if clipFileName != nil { return .done }
        if day == currentDay { return .today }
        if day < currentDay { return .missed }
        return .locked
    }
}
