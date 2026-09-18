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
    /// How big, relative to the size the style draws at. Pinch to change.
    var scale: Double
    /// How far it's turned, in degrees. Rotate with two fingers.
    var angle: Double
    /// What colour the words are.
    var tint: Tint

    /// Middle of the frame, a little above centre — where the caption has
    /// always been burned, so a card saved before stickers existed looks the
    /// same as it did.
    static let `default` = CaptionSticker(x: 0.5, y: 0.43, style: .outline)

    init(
        x: Double,
        y: Double,
        style: Style,
        scale: Double = 1,
        angle: Double = 0,
        tint: Tint = .white
    ) {
        // 0.08 keeps the sticker off the frame's edge, which is where the
        // stitcher's own margin is and where a phone's rounded corners eat it.
        self.x = min(max(x, 0.08), 0.92)
        self.y = min(max(y, 0.08), 0.92)
        self.style = style
        // Clamped for the same reason the position is: a pinch that ran away
        // leaves a caption too small to read or too big to fit, and there is no
        // reset button. Below 0.55 the smallest style is under 10pt at export.
        self.scale = min(max(scale.isFinite ? scale : 1, 0.55), 2.2)
        // Past about a third of a turn it stops reading as a tilted caption and
        // starts reading as a mistake.
        self.angle = min(max(angle.isFinite ? angle : 0, -35), 35)
        self.tint = tint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try c.decode(Double.self, forKey: .x),
            y: try c.decode(Double.self, forKey: .y),
            // A style added in a later version, read by an older one, is a
            // style that doesn't exist yet — draw the words rather than
            // throwing the whole card away.
            style: Style(rawValue: try c.decode(String.self, forKey: .style)) ?? .outline,
            // Added after stickers shipped. Absent means a caption saved before
            // they existed: unscaled, unturned, white — exactly how it looked.
            scale: try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1,
            angle: try c.decodeIfPresent(Double.self, forKey: .angle) ?? 0,
            tint: (try c.decodeIfPresent(String.self, forKey: .tint))
                .flatMap(Tint.init(rawValue:)) ?? .white)
    }

    /// What sits behind the words.
    ///
    /// Four offered, five stored. The four are a choice about legibility — the
    /// thing people actually hit is a caption swallowed by whatever is behind
    /// it — and they are shown as four samples rather than cycled by a button,
    /// because a button that cycles cannot say what it is about to pick.
    enum Style: String, Codable, CaseIterable, Identifiable {
        /// White rounded text with a soft shadow: the original, and the one
        /// that disappears into footage rather than sitting on top of it.
        case outline
        /// The same text on a dark rounded band — legible over a bright sky,
        /// which white-on-white is not.
        case band
        /// A hard black bar, like a subtitle. Covers what is behind it instead
        /// of sharing with it, which is the point.
        case solid
        /// White bar, dark words. The one that reads on a pale frame — snow, a
        /// white wall, an overexposed window — where all three above are a
        /// smudge.
        case light
        /// Big and heavy, for one or two words used as a title.
        ///
        /// No longer offered: size is a pinch now, so this was a second way to
        /// say the same thing. Still decoded, still drawn, because cards saved
        /// with it have to keep looking like themselves — `picker` is what the
        /// four squares read.
        case headline

        var id: String { rawValue }

        /// The four the picker shows, in the order it shows them.
        static let picker: [Style] = [.outline, .band, .solid, .light]

        /// Which square lights up for this style. `headline` borrows
        /// `outline`'s: it has no plate either.
        var pickerEquivalent: Style { self == .headline ? .outline : self }

        /// The bar behind the words, as numbers both renderers can use.
        ///
        /// Shared rather than duplicated because the review screen and the
        /// exporter have to agree to the pixel: the whole promise of placing a
        /// caption by hand is that the film comes out looking like the screen
        /// it was placed on.
        var plate: Plate? {
            switch self {
            case .outline, .headline: nil
            // Roomy and round: it reads as a soft pill behind a sentence.
            case .band: Plate(isWhite: false, opacity: 0.45, radius: 0.34, padH: 0.8, padV: 0.42)
            // Tighter and squarer, so it reads as a bar and not as a bubble.
            case .solid: Plate(isWhite: false, opacity: 1, radius: 0.14, padH: 0.62, padV: 0.3)
            case .light: Plate(isWhite: true, opacity: 0.94, radius: 0.14, padH: 0.62, padV: 0.3)
            }
        }
    }

    /// A caption's backing bar. Every measurement is a multiple of the font
    /// size except `radius`, which is a fraction of the bar's own height — so
    /// one description works at any caption size, on the phone and at export.
    struct Plate: Equatable {
        let isWhite: Bool
        let opacity: Double
        /// × the plate's height.
        let radius: Double
        /// × the font size.
        let padH: Double
        let padV: Double
    }

    /// The colour of the words.
    ///
    /// Twelve, in the order the picker draws them: two rows of six. It was six
    /// and they were all the brand's own, which made the row read as a palette
    /// belonging to the app rather than a choice belonging to the person —
    /// and it had no black, so a caption on snow or a white wall had nothing
    /// legible to be.
    enum Tint: String, Codable, CaseIterable, Identifiable {
        case white, black, blue, cyan, mint, butter
        case coral, rose, lavender, violet, blush, ink

        var id: String { rawValue }

        /// Whether words in this colour need a light plate under them rather
        /// than a dark one. Read by both renderers to keep black-on-black and
        /// white-on-white off the screen.
        var isDark: Bool { self == .black || self == .ink }
    }

    // MARK: - Keeping the pair readable

    /// The colour to use when `style` is picked.
    ///
    /// Tapping 白底 while the words are white, or 纯黑底 while they are black,
    /// asks for a caption that cannot be read. Rather than quietly drawing
    /// something else, the other half of the pair moves — and because both the
    /// colours and the backings are on screen together, the person sees it
    /// move. Whichever one was just tapped is the one that stays.
    static func legibleTint(picking style: Style, keeping tint: Tint) -> Tint {
        guard let plate = style.plate else { return tint }
        if plate.isWhite, tint == .white { return .black }
        if !plate.isWhite, tint.isDark { return .white }
        return tint
    }

    /// The backing to use when `tint` is picked. The mirror of the above: the
    /// swap is to the other bar of the same weight, not to no bar at all —
    /// somebody who chose a bar wants a bar.
    static func legibleStyle(picking tint: Tint, keeping style: Style) -> Style {
        guard let plate = style.plate else { return style }
        if plate.isWhite, tint == .white { return .solid }
        if !plate.isWhite, tint.isDark { return .light }
        return style
    }

    // MARK: - CloudKit

    /// One field rather than six, because two thirds of a sticker is not a
    /// sticker: a position without a style, or an x without a y, has nothing
    /// to draw. Also one schema change in the room's record type instead of
    /// six.
    ///
    /// Appended to rather than restructured: a three-part value is one written
    /// by a version before scale/angle/tint existed, and it has to keep
    /// meaning what it meant.
    var cloudValue: String {
        "\(x),\(y),\(style.rawValue),\(scale),\(angle),\(tint.rawValue)"
    }

    init?(cloudValue: String) {
        let parts = cloudValue.split(separator: ",")
        guard parts.count == 3 || parts.count == 6,
              let x = Double(parts[0]), let y = Double(parts[1]),
              let style = Style(rawValue: String(parts[2]))
        else { return nil }
        guard parts.count == 6 else {
            self.init(x: x, y: y, style: style)
            return
        }
        // A newer phone's extra fields, read by this one. Anything unparseable
        // falls back to the default for that field rather than dropping the
        // whole sticker — half a sticker still beats none.
        self.init(
            x: x, y: y, style: style,
            scale: Double(parts[3]) ?? 1,
            angle: Double(parts[4]) ?? 0,
            tint: Tint(rawValue: String(parts[5])) ?? .white)
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
