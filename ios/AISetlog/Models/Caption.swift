import Foundation

/// One line of somebody's own words on their own clip.
///
/// A clip used to hold exactly one: `overlayText` plus a `CaptionSticker`. Now
/// it holds a list, each with its own words and its own place and look, so a
/// clip can say 「早上好」 at the top and 「第一杯咖啡」 under the cup.
///
/// Stored on the card, the extra takes and the drafts as `captions`. A card
/// saved before this existed decodes as a list of one (`decodeList`), and every
/// save still writes the first caption back to the old `overlayText` /
/// `captionSticker` keys, so an older build reading the same file keeps
/// showing the first one.
struct Caption: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    /// Nil means nobody has moved it: drawn at `CaptionSticker.default`, which
    /// is where every caption was burned before stickers existed.
    var sticker: CaptionSticker?

    init(id: UUID = UUID(), text: String, sticker: CaptionSticker? = nil) {
        self.id = id
        self.text = text
        self.sticker = sticker
    }

    /// Where it is drawn.
    var placed: CaptionSticker { sticker ?? .default }

    /// The words as they are burned: trimmed, and nil when nothing is left.
    var trimmedText: String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    enum CodingKeys: String, CodingKey { case id, text, sticker }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An id is only for telling two captions apart on screen; a list
        // written without one (by hand, or by a future version that drops it)
        // still means the same words.
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        sticker = try c.decodeIfPresent(CaptionSticker.self, forKey: .sticker)
    }

    // MARK: - Old single-caption keys

    /// Reads `captions` if it is there, otherwise the single caption every
    /// earlier version wrote as `overlayText` + `captionSticker`.
    static func decodeList<K: CodingKey>(
        _ c: KeyedDecodingContainer<K>, list: K, text: K, sticker: K
    ) throws -> [Caption] {
        if let captions = try c.decodeIfPresent([Caption].self, forKey: list) {
            return captions
        }
        return .single(
            try c.decodeIfPresent(String.self, forKey: text),
            sticker: try c.decodeIfPresent(CaptionSticker.self, forKey: sticker))
    }

    /// Writes the list, and the first caption again under the old keys.
    static func encodeList<K: CodingKey>(
        _ captions: [Caption], into c: inout KeyedEncodingContainer<K>,
        list: K, text: K, sticker: K
    ) throws {
        try c.encode(captions, forKey: list)
        try c.encodeIfPresent(captions.firstText, forKey: text)
        try c.encodeIfPresent(captions.first?.sticker, forKey: sticker)
    }

    // MARK: - CloudKit

    /// The whole list as one string, for the `Clip` record's `captionsJSON`
    /// field. Nil for no captions, so an empty list clears the field.
    static func cloudJSON(_ captions: [Caption]) -> String? {
        guard !captions.isEmpty,
              let data = try? JSONEncoder().encode(captions)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// What a room record says its captions are.
    ///
    /// `captionsJSON` wins — but only while its first caption still says what
    /// `overlayText` says. Version 1.5 (31) doesn't know the new field: when it
    /// re-records or edits a caption it rewrites `overlayText` and leaves
    /// `captionsJSON` as it was, and showing the stale list over the words the
    /// person just typed would be the wrong one of the two. A list that
    /// doesn't parse is treated the same as no list.
    static func fromCloud(
        json: String?, overlayText: String?, sticker: CaptionSticker?
    ) -> [Caption] {
        let old = [Caption].single(overlayText, sticker: sticker)
        guard let json, let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([Caption].self, from: data)
        else { return old }
        let listFirst = list.firstText
        let oldFirst = old.firstText
        guard listFirst == oldFirst else { return old }
        return list
    }
}

extension Array where Element == Caption {
    /// A list of at most one, from the fields a clip had before it could hold
    /// more. Empty words are no caption.
    static func single(_ text: String?, sticker: CaptionSticker? = nil) -> [Caption] {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty
        else { return [] }
        return [Caption(text: t, sticker: sticker)]
    }

    /// The first caption's words, trimmed; nil when there are none.
    var firstText: String? { first?.trimmedText }

    /// Only the captions that have words in them, in order — what gets drawn.
    var drawable: [Caption] { filter { $0.trimmedText != nil } }

    /// Sets the first caption's words. Nil or blank removes the first caption,
    /// sticker and all: a caption deleted and typed again should not come back
    /// wherever the last one was dragged to.
    mutating func setFirstText(_ text: String?) {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let t, !t.isEmpty else {
            if !isEmpty { removeFirst() }
            return
        }
        if isEmpty {
            append(Caption(text: t))
        } else {
            self[0].text = t
        }
    }

    /// Moves the first caption. No caption, nothing to move.
    mutating func setFirstSticker(_ sticker: CaptionSticker?) {
        guard !isEmpty else { return }
        self[0].sticker = sticker
    }
}
