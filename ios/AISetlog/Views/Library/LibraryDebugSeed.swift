#if DEBUG
import Foundation

/// `-debugSeedLibrary YES`: fill 我的 with something to look at on a simulator
/// with no camera — two stories for today with clips, three drafts on earlier
/// days, and today's mood. Runs once per install (it sets a flag), and only in
/// Debug builds. The footage is the onboarding sample film, copied.
@MainActor
enum LibraryDebugSeed {
    private static let doneKey = "debugSeedLibrary.done"

    static func runIfAsked(store: ChallengeStore, drafts: ClipDraftStore, moods: MoodStore?) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "debugSeedLibrary"), !defaults.bool(forKey: doneKey),
              let sample = Bundle.main.url(forResource: "sample-film", withExtension: "mp4")
        else { return }
        defaults.set(true, forKey: doneKey)

        let day = store.createQuickStart()
        for slot in 1...3 { store.saveClip(from: copy(sample), day: slot, challengeID: day.id) }
        let week = store.create(
            title: AppLanguage.effective.resolved == .chinese ? "7 天早起" : "Early mornings", mode: .sevenDay)
        store.saveClip(from: copy(sample), day: 1, challengeID: week.id)

        for daysAgo in [1, 1, 3] {
            let at = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            _ = try? drafts.keep(tempURL: copy(sample), orientation: .portrait, recordedAt: at)
        }
        moods?.setMood(.happy)
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) {
            moods?.setMood(.calm, on: yesterday)
        }
    }

    private static func copy(_ url: URL) -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        try? FileManager.default.copyItem(at: url, to: temp)
        return temp
    }
}
#endif
