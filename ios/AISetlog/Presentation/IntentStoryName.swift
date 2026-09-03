import Foundation

/// The story's name, borrowed from the sentence that produced its prompts.
///
/// Saving needs a name, and the name field sits above a card the user has
/// scrolled past by the time they've read seven fresh prompts — so the save
/// button goes grey for a reason that is off-screen. Somebody who typed
/// "今天要搬家" has already named the story; asking them to type it again is
/// asking twice for the same answer.
///
/// The sentence is used as-is apart from punctuation. Trying to shorten
/// "今天要搬家" into "搬家" means guessing at grammar, and a guess that lands
/// wrong renames someone's story without being asked. A name they can see and
/// edit beats a clever one they didn't choose.
enum IntentStoryName {
    /// Past this, a sentence is a sentence rather than a title, and a bad
    /// default is worse than the empty field — which at least looks unfinished.
    static let lengthLimit = 24

    private static let edgePunctuation = CharacterSet(
        charactersIn: "。．.!！?？,，、;；:：~～…-—_ \t")

    /// - Returns: a usable name, or `nil` when the sentence doesn't make one.
    static func derive(from intent: String, limit: Int = lengthLimit) -> String? {
        let name = intent.trimmingCharacters(in: edgePunctuation.union(.whitespacesAndNewlines))
        guard !name.isEmpty, name.count <= limit else { return nil }
        return name
    }
}
