import Foundation

struct ClipReaction: Codable, Identifiable, Equatable {
    var emoji: String
    var authorID: String
    var authorName: String
    var createdAt: Date = .now

    var id: String { "\(authorID)|\(emoji)" }

    static let moodPrefix = "mood:"
    static let palette = Mood.allCases.map { moodPrefix + $0.rawValue }

    static func mood(for key: String) -> Mood? {
        guard key.hasPrefix(moodPrefix) else { return nil }
        return Mood(rawValue: String(key.dropFirst(moodPrefix.count)))
    }
}

struct ClipComment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var authorID: String
    var authorName: String
    var createdAt: Date = .now
}
