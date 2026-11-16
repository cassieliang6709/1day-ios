import Foundation

enum IntentStoryName {
    static let lengthLimit = 24

    private static let edgePunctuation = CharacterSet(
        charactersIn: "。．.!！?？,，、;；:：~～…-—_ \t")

    static func derive(from intent: String, limit: Int = lengthLimit) -> String? {
        let name = intent.trimmingCharacters(in: edgePunctuation.union(.whitespacesAndNewlines))
        guard !name.isEmpty, name.count <= limit else { return nil }
        return name
    }
}
