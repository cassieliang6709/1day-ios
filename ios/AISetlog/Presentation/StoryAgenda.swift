import Foundation

struct StoryAgenda: Equatable {
    let total: Int
    let filmed: [Int]
    let openToMe: [Int]
    let suggested: Int?

    init(momentCount: Int, clips: [DayClip], myID: String) {
        total = max(momentCount, 0)
        let slots = total > 0 ? Array(1...total) : []
        let anyones = Set(clips.map(\.day))
        let mine = Set(
            clips
                .filter { $0.authorID == myID || $0.authorID == RoomProgress.soloAuthorID }
                .map(\.day))

        filmed = slots.filter(anyones.contains)
        openToMe = slots.filter { !mine.contains($0) }
        suggested = slots.first { !anyones.contains($0) }
    }

    var filmedCount: Int { filmed.count }

    var isComplete: Bool { total > 0 && filmed.count >= total }

    func isAwaitingMine(slot: Int) -> Bool {
        filmed.contains(slot) && openToMe.contains(slot)
    }

    func isSuggested(slot: Int) -> Bool { suggested == slot }
}
