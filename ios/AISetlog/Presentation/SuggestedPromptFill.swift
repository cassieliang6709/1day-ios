import Foundation

enum StoryMoments {
    static let maxCount = 12
}

enum SuggestedPromptFill {
    static func apply(
        _ suggestions: [String],
        to answers: [String],
        replacing offered: [String] = [],
        limit: Int = StoryMoments.maxCount
    ) -> [String] {
        var remaining = suggestions
            .map(trimmed)
            .filter { !$0.isEmpty }
        guard !remaining.isEmpty else { return answers }
        let stale = Set(offered.map(trimmed).filter { !$0.isEmpty })

        var filled: [String] = []
        for row in answers {
            let isBlank = trimmed(row).isEmpty
            let isStale = !isBlank && stale.contains(trimmed(row))
            if (isBlank || isStale), !remaining.isEmpty {
                filled.append(remaining.removeFirst())
            } else if !isStale {
                filled.append(row)
            }
        }

        while !remaining.isEmpty, filled.count < limit {
            filled.append(remaining.removeFirst())
        }
        return filled
    }

    static func canReplace(_ answers: [String], offered: [String]) -> Bool {
        let stale = Set(offered.map(trimmed).filter { !$0.isEmpty })
        guard !stale.isEmpty else { return false }
        return answers.contains { stale.contains(trimmed($0)) }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
