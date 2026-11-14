import Foundation

/// Memoizes the DayClip list `ChallengeStore.recordedClips(for:)` builds.
///
/// The two resident home screens ask for every story's clips on every body
/// pass (`library`, `sharedStories`, each row's `cardState`). Rebuilding
/// Documents URLs, localizing moment titles, and filtering room reactions
/// is wasted work when the inputs have not changed.
final class RecordedClipListCache {
    /// Everything `recordedClips` reads to produce its list. Two calls with
    /// equal input must return the same clips; any visible change (new or
    /// deleted take, caption, reaction, comment, remote cache, sign-in, or
    /// app language) must miss the cache.
    struct Input: Equatable {
        var roomCode: String?
        var isTimeOnly: Bool
        var momentTitles: [String]?
        var cards: [DayCard]
        /// `nil` and `[]` are the same: both take the local-only path in
        /// `recordedClips`. A non-empty remote list is a different input.
        var remoteClips: [CloudKitService.RemoteClip]?
        var remoteReactions: [CloudKitService.RemoteReaction]
        var remoteComments: [CloudKitService.RemoteComment]
        var accountID: String?
        var displayName: String?
        var localeCode: String

        init(
            challenge: Challenge,
            remoteClips: [CloudKitService.RemoteClip]?,
            remoteReactions: [CloudKitService.RemoteReaction],
            remoteComments: [CloudKitService.RemoteComment],
            accountID: String?,
            displayName: String?,
            localeCode: String
        ) {
            self.roomCode = challenge.roomCode
            self.isTimeOnly = challenge.isTimeOnly
            self.momentTitles = challenge.momentTitles
            self.cards = challenge.cards
            self.remoteClips = (remoteClips?.isEmpty ?? true) ? nil : remoteClips
            self.remoteReactions = remoteReactions
            self.remoteComments = remoteComments
            self.accountID = accountID
            self.displayName = displayName
            self.localeCode = localeCode
        }
    }

    private struct Entry {
        let input: Input
        let clips: [DayClip]
    }

    private var entries: [UUID: Entry] = [:]
    /// How many times a compute closure has run. Tests use this to prove a
    /// second call with the same input did not rebuild the list.
    private(set) var computeCount = 0

    func clips(for id: UUID, input: Input, compute: () -> [DayClip]) -> [DayClip] {
        if let entry = entries[id], entry.input == input {
            return entry.clips
        }
        computeCount += 1
        let clips = compute()
        entries[id] = Entry(input: input, clips: clips)
        return clips
    }

    func remove(_ id: UUID) {
        entries[id] = nil
    }

    /// Drop entries for stories that are no longer in the store, so a
    /// deleted room does not keep its DayClip list alive.
    func keepOnly(ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
    }
}
