import Foundation

struct ClipDraft: Codable, Identifiable, Equatable {
    let id: UUID
    var fileName: String
    var recordedAt: Date
    var orientation: Challenge.Orientation
    var captions: [Caption]
    var overlayText: String? {
        get { captions.firstText }
        set { captions.setFirstText(newValue) }
    }
    var byteSize: Int64

    init(
        id: UUID = UUID(),
        fileName: String,
        recordedAt: Date = .now,
        orientation: Challenge.Orientation,
        overlayText: String? = nil,
        captions: [Caption]? = nil,
        byteSize: Int64 = 0
    ) {
        self.id = id
        self.fileName = fileName
        self.recordedAt = recordedAt
        self.orientation = orientation
        self.captions = captions ?? .single(overlayText)
        self.byteSize = byteSize
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, recordedAt, orientation, captions, overlayText, captionSticker, byteSize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fileName = try c.decode(String.self, forKey: .fileName)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        orientation = try c.decode(Challenge.Orientation.self, forKey: .orientation)
        captions = try Caption.decodeList(
            c, list: .captions, text: .overlayText, sticker: .captionSticker)
        byteSize = try c.decode(Int64.self, forKey: .byteSize)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(recordedAt, forKey: .recordedAt)
        try c.encode(orientation, forKey: .orientation)
        try Caption.encodeList(
            captions, into: &c, list: .captions, text: .overlayText, sticker: .captionSticker)
        try c.encode(byteSize, forKey: .byteSize)
    }
}
