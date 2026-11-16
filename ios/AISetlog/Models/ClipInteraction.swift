import Foundation

struct ClipReaction: Codable, Identifiable, Equatable {
    var emoji: String
    var authorID: String
    var authorName: String
    var createdAt: Date = .now

    var id: String { "\(authorID)|\(emoji)" }

    static let palette = ["🩵", "🥹", "😭", "🫶", "✨", "🐣"]
}

enum ClipReactionRecents {
    static let storageKey = "clip.reaction.recents.v1"
    static let limit = 8

    static func load(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }

    static func adding(_ emoji: String, to recents: [String]) -> [String] {
        ([emoji] + recents.filter { $0 != emoji }).prefix(limit).map { $0 }
    }

    static func suggestions(recents: [String]) -> [String] {
        recents + ClipReaction.palette.filter { !recents.contains($0) }
    }
}

struct ClipComment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var authorID: String
    var authorName: String
    var createdAt: Date = .now
}
