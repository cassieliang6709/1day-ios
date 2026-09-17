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

    /// What the picker offers before you've used anything else. Not a limit:
    /// `id` is `authorID|emoji`, so toggling and de-duping work for any emoji,
    /// and `ClipReactionRecents` remembers the ones you actually reach for.
    static let palette = ["🩵", "🥹", "😭", "🫶", "✨", "🐣"]
}

/// The emoji this person has used, most recent first.
///
/// The bar used to draw all six of `palette` as always-on dark pills, whether
/// anybody had reacted or not — six buttons for a feature most clips never use,
/// and no way to leave anything that wasn't one of the six. Now the bar shows
/// only what's actually there, and the picker leads with your own history.
enum ClipReactionRecents {
    static let storageKey = "clip.reaction.recents.v1"
    /// Enough to cover a personal habit, few enough to fit one row.
    static let limit = 8

    static func load(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }

    /// Most recent first, de-duplicated, capped. Returned rather than stored
    /// by the caller's binding so this stays testable without `UserDefaults`.
    static func adding(_ emoji: String, to recents: [String]) -> [String] {
        ([emoji] + recents.filter { $0 != emoji }).prefix(limit).map { $0 }
    }

    /// What the picker shows: your history, then the defaults you haven't used.
    static func suggestions(recents: [String]) -> [String] {
        recents + ClipReaction.palette.filter { !recents.contains($0) }
    }
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
