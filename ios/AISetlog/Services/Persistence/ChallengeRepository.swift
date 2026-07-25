import Foundation

/// Persistence boundary for challenges and custom templates. The store keeps
/// state in memory; this owns reading/writing it (UserDefaults today,
/// SwiftData tomorrow — swap the implementation, nothing else changes).
protocol ChallengeRepository {
    func loadChallenges() -> [Challenge]
    func saveChallenges(_ challenges: [Challenge])
    func loadTemplates() -> [ChallengeTemplate]
    func saveTemplates(_ templates: [ChallengeTemplate])
}

/// UserDefaults-backed repository, including the v1 → v2 data migration
/// (a single id-less challenge with clips loose in clips/).
final class UserDefaultsChallengeRepository: ChallengeRepository {
    static let defaultsKey = "challenges.v2"
    private static let legacyKey = "challenge.v1"
    private static let templatesKey = "customTemplates.v1"

    private let defaults: UserDefaults
    private let fileStore: ClipFileStore

    init(defaults: UserDefaults = .standard, fileStore: ClipFileStore = DiskClipFileStore()) {
        self.defaults = defaults
        self.fileStore = fileStore
    }

    func loadChallenges() -> [Challenge] {
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Challenge].self, from: data) {
            return saved
        }
        return migrateLegacyIfNeeded()
    }

    func saveChallenges(_ challenges: [Challenge]) {
        if let data = try? JSONEncoder().encode(challenges) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    func loadTemplates() -> [ChallengeTemplate] {
        guard let data = defaults.data(forKey: Self.templatesKey),
              let saved = try? JSONDecoder().decode([ChallengeTemplate].self, from: data)
        else { return [] }
        return saved
    }

    func saveTemplates(_ templates: [ChallengeTemplate]) {
        if let data = try? JSONEncoder().encode(templates) {
            defaults.set(data, forKey: Self.templatesKey)
        }
    }

    /// v1 stored a single challenge without an id, clips directly in clips/.
    private func migrateLegacyIfNeeded() -> [Challenge] {
        struct LegacyChallenge: Codable {
            var title: String
            var startDate: Date
            var cards: [DayCard]
        }
        guard let data = defaults.data(forKey: Self.legacyKey),
              let old = try? JSONDecoder().decode(LegacyChallenge.self, from: data)
        else { return [] }

        let migrated = Challenge(
            id: UUID(), title: old.title, startDate: old.startDate, cards: old.cards)
        let challenges = [migrated]
        fileStore.migrateLegacyClips(
            old.cards.compactMap(\.clipFileName), into: migrated.id)
        saveChallenges(challenges)
        defaults.removeObject(forKey: Self.legacyKey)
        return challenges
    }
}
