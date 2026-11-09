import Foundation

/// A clip that was recorded but not filed into a story yet.
///
/// Free-form recording writes into the system temp directory, so a clip only
/// survives if something copies it somewhere permanent. Before drafts existed,
/// the two paths that couldn't file a clip (no stories yet, or no story with a
/// matching frame) just showed a toast — and the clip died with the screen.
/// A draft is that missing destination: somewhere a clip can wait until there
/// is a story to put it in.
struct ClipDraft: Codable, Identifiable, Equatable {
    let id: UUID
    /// File name inside the drafts directory — never a temp path, because a
    /// temp path is exactly what a draft exists to escape.
    var fileName: String
    var recordedAt: Date
    var orientation: Challenge.Orientation
    /// The words typed on it, kept until it is filed. See `Caption`.
    var captions: [Caption]
    /// The first caption's words — all a draft could hold before.
    var overlayText: String? {
        get { captions.firstText }
        set { captions.setFirstText(newValue) }
    }
    /// Cached at save time so the drafts list can show what it costs to keep.
    /// Drafts have no expiry yet, so the only thing stopping them from filling
    /// the phone is the person looking at that number.
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
        // Drafts saved before a clip could hold several captions have one
        // `overlayText` and no `captions`.
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
