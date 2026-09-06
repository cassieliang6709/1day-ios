import Foundation

/// What the generated-prompts feature is actually here to find out.
///
/// The feature is worth shipping on its own, but the reason it comes first is
/// the question underneath it: **will people film what a model tells them to
/// film?** That question decides whether a much larger idea — say what you want
/// to shoot, get a script, go shoot it — is a product or a daydream. Adoption
/// and rewrite rates answer it with numbers instead of opinions.
///
/// Local only. Nothing here is sent anywhere; it's a counter you can read off
/// a device you're holding. Sending a person's own prompts to a server to
/// measure how much they liked them would be a strange thing to do to them.
@Observable
final class PromptSuggestionMetrics {
    /// Position-keyed so "did they rewrite the beginning or the end" is
    /// answerable. If the last two get rewritten every time, the model is bad
    /// at endings, not bad at prompts.
    struct Snapshot: Codable, Equatable {
        /// Times a generation came back with prompts.
        var generated = 0
        /// Times a generated set was carried into a real story.
        var adopted = 0
        /// Total prompts handed to a user across all adopted sets.
        var promptsOffered = 0
        /// How many of those had been changed by the time the story was made.
        var promptsEdited = 0
        /// 1-based position → times a prompt in that slot was edited.
        var editsByPosition: [Int: Int] = [:]

        /// 0…1, or nil before anything has been adopted.
        var editRate: Double? {
            promptsOffered > 0 ? Double(promptsEdited) / Double(promptsOffered) : nil
        }

        var adoptionRate: Double? {
            generated > 0 ? Double(adopted) / Double(generated) : nil
        }
    }

    private(set) var snapshot: Snapshot {
        didSet { save() }
    }

    static let storageKey = "promptSuggestion.metrics.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            ?? Snapshot()
    }

    func recordGenerated() {
        snapshot.generated += 1
    }

    /// Called when a generated set becomes a story, with the prompts as saved.
    ///
    /// A prompt counts as edited if the text changed at all, and a deleted one
    /// counts too: throwing a prompt away is the strongest edit there is.
    func recordAdopted(offered: [String], saved: [String]) {
        guard !offered.isEmpty else { return }
        snapshot.adopted += 1
        snapshot.promptsOffered += offered.count

        for (index, prompt) in offered.enumerated() where !saved.contains(prompt) {
            snapshot.promptsEdited += 1
            snapshot.editsByPosition[index + 1, default: 0] += 1
        }
    }

    /// For the debug readout in Settings; also what the tests reset between runs.
    func reset() {
        snapshot = Snapshot()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
