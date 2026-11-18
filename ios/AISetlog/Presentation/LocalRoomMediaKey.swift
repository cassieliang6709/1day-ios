import Foundation

enum LocalRoomMediaKey {
    static func make(day: Int, clips: [DayClip]) -> String {
        let fields = [String(day)] + clips.flatMap { [$0.id, $0.url.absoluteString, $0.overlayText ?? ""] }
        return fields.map { "\($0.utf8.count):\($0)" }.joined()
    }
}
