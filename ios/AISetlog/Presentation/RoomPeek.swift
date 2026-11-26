import Foundation

struct RoomPeek: Equatable {
    let iFilmedToday: Bool

    private let myID: String
    private let today: Date
    private let calendar: Calendar

    init(clips: [DayClip], myID: String, now: Date, calendar: Calendar = .current) {
        self.myID = myID
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        let isToday: (DayClip) -> Bool = { clip in
            clip.recordedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }
        iFilmedToday = clips.contains { ClipDeck.isMine($0, myID: myID) && isToday($0) }
    }

    func isLocked(_ clip: DayClip) -> Bool {
        guard !iFilmedToday, !ClipDeck.isMine(clip, myID: myID),
              let at = clip.recordedAt
        else { return false }
        return calendar.isDate(at, inSameDayAs: today)
    }

    func visible(_ clips: [DayClip]) -> [DayClip] {
        clips.filter { !isLocked($0) }
    }
}
