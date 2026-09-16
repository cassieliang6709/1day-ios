import Foundation

/// Where a person's own words sit on their own footage, and how they're drawn.
///
/// The caption used to be burned 43% down the middle of every frame, the same
/// spot for everybody — which is the spot a face is usually in. It's a sticker
/// instead: you put it where it belongs on *your* picture, over the sky or
/// under the person or off to one side, and the film burns it exactly where the
/// review screen showed it.
struct CaptionSticker: Codable, Equatable {
    /// The middle of the sticker, as a fraction of the frame it sits on.
    /// Clamped on the way in, because a sticker outside the frame is a caption
    /// nobody can read and no gesture can bring back.
    var x: Double
    var y: Double
    var style: Style

    /// Middle of the frame, a little above centre — where the caption has
    /// always been burned, so a card saved before stickers existed looks the
    /// same as it did.
    static let `default` = CaptionSticker(x: 0.5, y: 0.43, style: .outline)

    init(x: Double, y: Double, style: Style) {
        // 0.08 keeps the sticker off the frame's edge, which is where the
        // stitcher's own margin is and where a phone's rounded corners eat it.
        self.x = min(max(x, 0.08), 0.92)
        self.y = min(max(y, 0.08), 0.92)
        self.style = style
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try c.decode(Double.self, forKey: .x),
            y: try c.decode(Double.self, forKey: .y),
            // A style added in a later version, read by an older one, is a
            // style that doesn't exist yet — draw the words rather than
            // throwing the whole card away.
            style: Style(rawValue: try c.decode(String.self, forKey: .style)) ?? .outline)
    }

    /// How the words are drawn. Three, because a fourth would be a font picker.
    enum Style: String, Codable, CaseIterable, Identifiable {
        /// White rounded text with a soft shadow: the original, and the one
        /// that disappears into footage rather than sitting on top of it.
        case outline
        /// The same text on a dark rounded band — legible over a bright sky,
        /// which white-on-white is not.
        case band
        /// Big and heavy, for one or two words used as a title.
        case headline

        var id: String { rawValue }
    }

    // MARK: - CloudKit

    /// One field rather than three, because two thirds of a sticker is not a
    /// sticker: a position without a style, or an x without a y, has nothing
    /// to draw. Also one schema change in the room's record type instead of
    /// three.
    var cloudValue: String { "\(x),\(y),\(style.rawValue)" }

    init?(cloudValue: String) {
        let parts = cloudValue.split(separator: ",")
        guard parts.count == 3,
              let x = Double(parts[0]), let y = Double(parts[1]),
              let style = Style(rawValue: String(parts[2]))
        else { return nil }
        self.init(x: x, y: y, style: style)
    }
}

struct DayCard: Codable, Identifiable {
    let day: Int
    var clipFileName: String?
    var recordedAt: Date?
    var overlayText: String?
    /// Where `overlayText` sits. Nil means nobody has moved it, which draws it
    /// at `CaptionSticker.default`.
    var captionSticker: CaptionSticker?
    var reactions: [ClipReaction] = []
    var comments: [ClipComment] = []

    var id: Int { day }

    init(
        day: Int,
        clipFileName: String? = nil,
        recordedAt: Date? = nil,
        overlayText: String? = nil,
        captionSticker: CaptionSticker? = nil,
        reactions: [ClipReaction] = [],
        comments: [ClipComment] = []
    ) {
        self.day = day
        self.clipFileName = clipFileName
        self.recordedAt = recordedAt
        self.overlayText = overlayText
        self.captionSticker = captionSticker
        self.reactions = reactions
        self.comments = comments
    }

    enum CodingKeys: String, CodingKey {
        case day, clipFileName, recordedAt, overlayText, captionSticker, reactions, comments
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
        captionSticker = try c.decodeIfPresent(CaptionSticker.self, forKey: .captionSticker)
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
