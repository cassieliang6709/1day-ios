import Foundation

/// A single emoji left on a clip. One per (author, emoji) pair, so tapping the
/// same emoji again toggles it off. Local-first; mirrored to a room when shared.
struct ClipReaction: Codable, Identifiable, Equatable {
    var emoji: String
    var authorID: String
    var authorName: String
    var createdAt: Date = .now

    /// Stable across the same person's same emoji — drives toggle + dedupe.
    var id: String { "\(authorID)|\(emoji)" }

    /// The fixed palette offered in the reaction bar.
    static let palette = ["❤️", "🔥", "😂", "👏", "🥹", "✨"]
}

/// A short text note someone left on a clip. A "reply" is just another comment —
/// no threading in v1, which keeps the sync + UI shippable.
struct ClipComment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var authorID: String
    var authorName: String
    var createdAt: Date = .now
}
