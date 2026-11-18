import Foundation

struct CaptionSticker: Codable, Equatable {
    var x: Double
    var y: Double
    var style: Style
    var scale: Double
    var angle: Double
    var tint: Tint

    static let `default` = CaptionSticker(x: 0.5, y: 0.43, style: .outline)

    init(
        x: Double,
        y: Double,
        style: Style,
        scale: Double = 1,
        angle: Double = 0,
        tint: Tint = .white
    ) {
        self.x = min(max(x, 0.08), 0.92)
        self.y = min(max(y, 0.08), 0.92)
        self.style = style
        self.scale = min(max(scale.isFinite ? scale : 1, 0.55), 2.2)
        self.angle = min(max(angle.isFinite ? angle : 0, -35), 35)
        self.tint = tint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try c.decode(Double.self, forKey: .x),
            y: try c.decode(Double.self, forKey: .y),
            style: Style(rawValue: try c.decode(String.self, forKey: .style)) ?? .outline,
            scale: try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1,
            angle: try c.decodeIfPresent(Double.self, forKey: .angle) ?? 0,
            tint: (try c.decodeIfPresent(String.self, forKey: .tint))
                .flatMap(Tint.init(rawValue:)) ?? .white)
    }

    enum Style: String, Codable, CaseIterable, Identifiable {
        case outline
        case band
        case solid
        case light
        case headline

        var id: String { rawValue }

        static let picker: [Style] = [.outline, .band, .solid, .light]

        var pickerEquivalent: Style { self == .headline ? .outline : self }

        var plate: Plate? {
            switch self {
            case .outline, .headline: nil
            case .band: Plate(isWhite: false, opacity: 0.45, radius: 0.34, padH: 0.8, padV: 0.42)
            case .solid: Plate(isWhite: false, opacity: 1, radius: 0.14, padH: 0.62, padV: 0.3)
            case .light: Plate(isWhite: true, opacity: 0.94, radius: 0.14, padH: 0.62, padV: 0.3)
            }
        }
    }

    struct Plate: Equatable {
        let isWhite: Bool
        let opacity: Double
        let radius: Double
        let padH: Double
        let padV: Double
    }

    enum Tint: String, Codable, CaseIterable, Identifiable {
        case white, black, blue, cyan, mint, butter
        case coral, rose, lavender, violet, blush, ink

        var id: String { rawValue }

        var isDark: Bool { self == .black || self == .ink }
    }


    static func legibleTint(picking style: Style, keeping tint: Tint) -> Tint {
        guard let plate = style.plate else { return tint }
        if plate.isWhite, tint == .white { return .black }
        if !plate.isWhite, tint.isDark { return .white }
        return tint
    }

    static func legibleStyle(picking tint: Tint, keeping style: Style) -> Style {
        guard let plate = style.plate else { return style }
        if plate.isWhite, tint == .white { return .solid }
        if !plate.isWhite, tint.isDark { return .light }
        return style
    }


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
        self.init(
            x: x, y: y, style: style,
            scale: Double(parts[3]) ?? 1,
            angle: Double(parts[4]) ?? 0,
            tint: Tint(rawValue: String(parts[5])) ?? .white)
    }
}

enum TakeTarget: Hashable {
    case replace(UUID?)
    case append
}

struct ClipTake: Codable, Identifiable, Equatable {
    let id: UUID
    var fileName: String
    var recordedAt: Date
    var captions: [Caption] = []

    var overlayText: String? {
        get { captions.firstText }
        set { captions.setFirstText(newValue) }
    }

    var captionSticker: CaptionSticker? {
        get { captions.first?.sticker }
        set { captions.setFirstSticker(newValue) }
    }

    init(id: UUID, fileName: String, recordedAt: Date, captions: [Caption]) {
        self.id = id
        self.fileName = fileName
        self.recordedAt = recordedAt
        self.captions = captions
    }

    init(
        id: UUID, fileName: String, recordedAt: Date,
        overlayText: String?, captionSticker: CaptionSticker?
    ) {
        self.init(
            id: id, fileName: fileName, recordedAt: recordedAt,
            captions: .single(overlayText, sticker: captionSticker))
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, recordedAt, captions, overlayText, captionSticker
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fileName = try c.decode(String.self, forKey: .fileName)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        captions = try Caption.decodeList(
            c, list: .captions, text: .overlayText, sticker: .captionSticker)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(recordedAt, forKey: .recordedAt)
        try Caption.encodeList(
            captions, into: &c, list: .captions, text: .overlayText, sticker: .captionSticker)
    }
}

struct DayCard: Codable, Identifiable {
    var day: Int
    var clipFileName: String?
    var recordedAt: Date?
    var captions: [Caption] = []
    var reactions: [ClipReaction] = []
    var comments: [ClipComment] = []
    var moreTakes: [ClipTake] = []

    var id: Int { day }

    var overlayText: String? {
        get { captions.firstText }
        set { captions.setFirstText(newValue) }
    }

    var captionSticker: CaptionSticker? {
        get { captions.first?.sticker }
        set { captions.setFirstSticker(newValue) }
    }

    init(
        day: Int,
        clipFileName: String? = nil,
        recordedAt: Date? = nil,
        overlayText: String? = nil,
        captionSticker: CaptionSticker? = nil,
        captions: [Caption]? = nil,
        reactions: [ClipReaction] = [],
        comments: [ClipComment] = [],
        moreTakes: [ClipTake] = []
    ) {
        self.day = day
        self.clipFileName = clipFileName
        self.recordedAt = recordedAt
        self.captions = captions ?? .single(overlayText, sticker: captionSticker)
        self.reactions = reactions
        self.comments = comments
        self.moreTakes = moreTakes
    }

    enum CodingKeys: String, CodingKey {
        case day, clipFileName, recordedAt, overlayText, captionSticker, reactions, comments
        case moreTakes, captions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(Int.self, forKey: .day)
        clipFileName = try c.decodeIfPresent(String.self, forKey: .clipFileName)
        recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt)
        captions = try Caption.decodeList(
            c, list: .captions, text: .overlayText, sticker: .captionSticker)
        reactions = try c.decodeIfPresent([ClipReaction].self, forKey: .reactions) ?? []
        comments = try c.decodeIfPresent([ClipComment].self, forKey: .comments) ?? []
        moreTakes = try c.decodeIfPresent([ClipTake].self, forKey: .moreTakes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(day, forKey: .day)
        try c.encodeIfPresent(clipFileName, forKey: .clipFileName)
        try c.encodeIfPresent(recordedAt, forKey: .recordedAt)
        try Caption.encodeList(
            captions, into: &c, list: .captions, text: .overlayText, sticker: .captionSticker)
        try c.encode(reactions, forKey: .reactions)
        try c.encode(comments, forKey: .comments)
        try c.encode(moreTakes, forKey: .moreTakes)
    }

    enum Status: Equatable {
        case done
        case today
        case missed
        case locked
    }

    func status(currentDay: Int) -> Status {
        if clipFileName != nil { return .done }
        if day == currentDay { return .today }
        if day < currentDay { return .missed }
        return .locked
    }
}
