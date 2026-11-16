import Foundation

struct Caption: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var sticker: CaptionSticker?

    init(id: UUID = UUID(), text: String, sticker: CaptionSticker? = nil) {
        self.id = id
        self.text = text
        self.sticker = sticker
    }

    var placed: CaptionSticker { sticker ?? .default }

    var trimmedText: String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    enum CodingKeys: String, CodingKey { case id, text, sticker }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        sticker = try c.decodeIfPresent(CaptionSticker.self, forKey: .sticker)
    }


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

    static func encodeList<K: CodingKey>(
        _ captions: [Caption], into c: inout KeyedEncodingContainer<K>,
        list: K, text: K, sticker: K
    ) throws {
        try c.encode(captions, forKey: list)
        try c.encodeIfPresent(captions.firstText, forKey: text)
        try c.encodeIfPresent(captions.first?.sticker, forKey: sticker)
    }


    static func cloudJSON(_ captions: [Caption]) -> String? {
        guard !captions.isEmpty,
              let data = try? JSONEncoder().encode(captions)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

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
    static func single(_ text: String?, sticker: CaptionSticker? = nil) -> [Caption] {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty
        else { return [] }
        return [Caption(text: t, sticker: sticker)]
    }

    var firstText: String? { first?.trimmedText }

    var drawable: [Caption] { filter { $0.trimmedText != nil } }

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

    mutating func setFirstSticker(_ sticker: CaptionSticker?) {
        guard !isEmpty else { return }
        self[0].sticker = sticker
    }
}
