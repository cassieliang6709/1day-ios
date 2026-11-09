import Foundation

/// How many moments one story can hold, everywhere a list of them is edited.
///
/// It used to be three different numbers — seven in the guided writer, twelve
/// in the composer, none at all in the template builder — so a list built in
/// one place could be refused or silently truncated in the next.
enum StoryMoments {
    static let maxCount = 12
}

/// Where generated prompts land in a list somebody may already have typed in.
///
/// The rule is one line long and it's the whole point: what the user wrote
/// wins. A generator that silently overwrites the sentence you just typed is
/// worse than no generator, because now you can't trust it with the next one.
enum SuggestedPromptFill {
    /// - Parameters:
    ///   - answers: the list as it stands, blanks included.
    ///   - offered: what the previous round of generation put in. A row that
    ///     still reads exactly like one of these was never touched by a person,
    ///     so it is the generator's to swap out — that's what makes a second
    ///     tap ("换一批") do something instead of nothing on a full list.
    /// - Returns: the same list with the user's own rows untouched, blanks and
    ///   untouched offered rows filled from `suggestions` in order, untouched
    ///   offered rows the new round has no replacement for dropped (they belong
    ///   to the set being replaced), and any remainder appended up to `limit`.
    ///   An empty `suggestions` returns the list unchanged, which is also what
    ///   a failed generation does.
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

    /// Whether the generate button should read as "another set": there is a
    /// previous round and at least one of its rows is still on the list as
    /// offered. Once every row has been edited, generating only fills blanks
    /// again, so the plain label is the honest one.
    static func canReplace(_ answers: [String], offered: [String]) -> Bool {
        let stale = Set(offered.map(trimmed).filter { !$0.isEmpty })
        guard !stale.isEmpty else { return false }
        return answers.contains { stale.contains(trimmed($0)) }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
