import Foundation

protocol ChallengeRepository {
    func loadChallenges() -> [Challenge]
    func saveChallenges(_ challenges: [Challenge])
}

final class UserDefaultsChallengeRepository: ChallengeRepository {
    static let defaultsKey = "challenges.v2"
    private static let legacyKey = "challenge.v1"
    static let retiredTemplateKeys = ["customTemplates.v2", "customTemplates.v1"]

    private let defaults: UserDefaults
    private let fileStore: ClipFileStore

    init(defaults: UserDefaults = .standard, fileStore: ClipFileStore = DiskClipFileStore()) {
        self.defaults = defaults
        self.fileStore = fileStore
        removeRetiredTemplates()
    }

    private func removeRetiredTemplates() {
        for key in Self.retiredTemplateKeys { defaults.removeObject(forKey: key) }
        guard defaults === UserDefaults.standard else { return }
        let covers = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("templateCovers", isDirectory: true)
        try? FileManager.default.removeItem(at: covers)
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
