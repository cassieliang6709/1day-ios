import Foundation

enum ClipFiling {
    static func rooms(in challenges: [Challenge]) -> [Challenge] {
        challenges.filter { $0.isShared && !$0.cards.isEmpty }
    }

    static func candidates(in challenges: [Challenge]) -> [Challenge] {
        challenges.filter { targetDay(in: $0) != nil }
    }

    static func targetDay(in challenge: Challenge) -> Int? {
        challenge.cards.first(where: { $0.clipFileName == nil })?.day
    }
}
