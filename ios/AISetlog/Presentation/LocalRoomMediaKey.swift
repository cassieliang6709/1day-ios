import Foundation

/// Stable clip identity is not a media revision. Production re-recordings can
/// even reuse the same URL. Include everything the moment burns into its frames.
enum LocalRoomMediaKey {
    private struct CaptionFrame: Encodable {
        let text: String
        let sticker: CaptionSticker
    }

    static func make(day: Int, clips: [DayClip]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let fields = [String(day)] + clips.flatMap { clip -> [String] in
            // UUIDs identify editable captions, not their pixels. Legacy wire
            // data can rebuild those UUIDs on an otherwise unchanged sync.
            let frames = clip.captions.map { CaptionFrame(text: $0.text, sticker: $0.placed) }
            let captions = (try? encoder.encode(frames))
                .map { String(decoding: $0, as: UTF8.self) } ?? String(reflecting: clip.captions)
            return [clip.id, String(clip.day), clip.url.absoluteString,
                    clip.recordedAt.map { String($0.timeIntervalSince1970) } ?? "",
                    clip.authorID ?? "", clip.authorName ?? "", clip.label ?? "", captions]
                + [String(clip.emoji.count)] + clip.emoji
                + [String(clip.comments.count)] + clip.comments
        }
        return fields.map { "\($0.utf8.count):\($0)" }.joined()
    }
}
