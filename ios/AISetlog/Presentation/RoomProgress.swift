import Foundation

struct RoomProgress: Equatable {
    let total: Int
    let filled: Int
    let mine: Int
    let clipCount: Int

    private let filledDays: Set<Int>

    static let soloAuthorID = "local"

    init(momentCount: Int, clips: [DayClip], myID: String) {
        total = max(momentCount, 0)
        clipCount = clips.count
        let story = 1...max(momentCount, 1)
        let inStory = { (day: Int) in momentCount > 0 && story.contains(day) }
        let days = Set(clips.map(\.day).filter(inStory))
        filledDays = days
        filled = days.count
        mine = Set(
            clips
                .filter { $0.authorID == myID || $0.authorID == Self.soloAuthorID }
                .map(\.day)
                .filter(inStory)
        ).count
    }

    var hasOthers: Bool { filled > mine }

    var isComplete: Bool { total > 0 && filled >= total }

    func isFilled(_ slot: Int) -> Bool { filledDays.contains(slot) }

    var nextOpenMoment: Int {
        guard total > 0 else { return 1 }
        return (1...total).first { !filledDays.contains($0) } ?? total
    }

    func slotToOffer(today: Int?) -> Int {
        guard total > 0 else { return 1 }
        guard let today else { return nextOpenMoment }
        let clamped = min(max(today, 1), total)
        return filledDays.contains(clamped) ? nextOpenMoment : clamped
    }

    func offeringToday(today: Int?) -> Bool {
        guard let today, total > 0 else { return true }
        return slotToOffer(today: today) == min(max(today, 1), total)
    }
}
