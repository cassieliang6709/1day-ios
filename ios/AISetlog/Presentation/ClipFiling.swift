import Foundation

enum ClipFiling {
    static func rooms(
        in challenges: [Challenge], orientation: Challenge.Orientation
    ) -> [Challenge] {
        challenges.filter { $0.isShared && $0.resolvedOrientation == orientation && !$0.cards.isEmpty }
    }

    static func candidates(
        in challenges: [Challenge], orientation: Challenge.Orientation
    ) -> [Challenge] {
        challenges.filter {
            $0.resolvedOrientation == orientation && targetDay(in: $0) != nil
        }
    }

    static func targetDay(in challenge: Challenge) -> Int? {
        challenge.cards.first(where: { $0.clipFileName == nil })?.day
    }

    enum Blocker: Equatable {
        case noStoryWithThisFrame
        case everyMatchingStoryIsFull
    }

    static func blocker(
        in challenges: [Challenge], orientation: Challenge.Orientation
    ) -> Blocker? {
        guard candidates(in: challenges, orientation: orientation).isEmpty else {
            return nil
        }
        return challenges.contains { $0.resolvedOrientation == orientation }
            ? .everyMatchingStoryIsFull
            : .noStoryWithThisFrame
    }
}
