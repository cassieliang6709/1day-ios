import Foundation

@Observable
final class PromptSuggestionMetrics {
    struct Snapshot: Codable, Equatable {
        var generated = 0
        var adopted = 0
        var promptsOffered = 0
        var promptsEdited = 0
        var editsByPosition: [Int: Int] = [:]

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

    func recordAdopted(offered: [String], saved: [String]) {
        guard !offered.isEmpty else { return }
        snapshot.adopted += 1
        snapshot.promptsOffered += offered.count

        for (index, prompt) in offered.enumerated() where !saved.contains(prompt) {
            snapshot.promptsEdited += 1
            snapshot.editsByPosition[index + 1, default: 0] += 1
        }
    }

    func reset() {
        snapshot = Snapshot()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
