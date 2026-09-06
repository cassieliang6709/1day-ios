import Foundation

/// Where generated prompts land in a list somebody may already have typed in.
///
/// The rule is one line long and it's the whole point: what the user wrote
/// wins. A generator that silently overwrites the sentence you just typed is
/// worse than no generator, because now you can't trust it with the next one.
enum SuggestedPromptFill {
    /// - Parameter answers: the list as it stands, blanks included.
    /// - Returns: the same list with the user's own rows untouched, blanks
    ///   filled from `suggestions` in order, and any remainder appended up to
    ///   `limit`. An empty `suggestions` returns the list unchanged, which is
    ///   also what a failed generation does.
    static func apply(
        _ suggestions: [String],
        to answers: [String],
        limit: Int = 7
    ) -> [String] {
        var remaining = suggestions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !remaining.isEmpty else { return answers }

        var filled = answers.map { row -> String in
            guard row.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !remaining.isEmpty
            else { return row }
            return remaining.removeFirst()
        }

        while !remaining.isEmpty, filled.count < limit {
            filled.append(remaining.removeFirst())
        }
        return filled
    }
}
