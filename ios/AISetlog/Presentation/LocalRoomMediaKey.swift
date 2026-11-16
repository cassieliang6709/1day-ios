import Foundation

enum LocalRoomMediaKey {
    private struct CaptionFrame: Encodable {
        let text: String
        let sticker: CaptionSticker
    }

    static func make(day: Int, clips: [DayClip]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var fields: [String] = [String(day)]
        for clip in clips {
            // UUIDs identify editable captions, not their pixels. Legacy wire
            // data can rebuild those UUIDs on an otherwise unchanged sync.
            let frames: [CaptionFrame] = clip.captions.map { CaptionFrame(text: $0.text, sticker: $0.placed) }
            let captions: String
            if let data = try? encoder.encode(frames) {
                captions = String(decoding: data, as: UTF8.self)
            } else {
                captions = String(reflecting: clip.captions)
            }
            let recordedAt: String = clip.recordedAt.map { String($0.timeIntervalSince1970) } ?? ""
            fields.append(clip.id)
            fields.append(String(clip.day))
            fields.append(clip.url.absoluteString)
            fields.append(recordedAt)
            fields.append(clip.authorID ?? "")
            fields.append(clip.authorName ?? "")
            fields.append(clip.label ?? "")
            fields.append(captions)
            fields.append(String(clip.emoji.count))
            fields.append(contentsOf: clip.emoji)
            fields.append(String(clip.comments.count))
            fields.append(contentsOf: clip.comments)
        }
        return fields.map { "\($0.utf8.count):\($0)" }.joined()
    }
}
