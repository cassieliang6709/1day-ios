import Foundation

struct ClipDeck {
    let clips: [DayClip]

    private let myID: String
    private let storyMomentCount: Int

    init(clips: [DayClip], momentCount: Int, myID: String) {
        self.myID = myID
        self.storyMomentCount = max(momentCount, clips.map(\.day).max() ?? 0)
        self.clips = clips.sorted {
            Self.sortKey($0, myID: myID) < Self.sortKey($1, myID: myID)
        }
    }

    private static func sortKey(
        _ clip: DayClip, myID: String
    ) -> (Int, Int, String, String) {
        (clip.day, isMine(clip, myID: myID) ? 0 : 1, clip.authorName ?? "", clip.id)
    }

    static func isMine(_ clip: DayClip, myID: String) -> Bool {
        guard let authorID = clip.authorID else { return true }
        return authorID == myID || authorID == RoomProgress.soloAuthorID
    }

    var count: Int { clips.count }
    var isEmpty: Bool { clips.isEmpty }

    func clip(at index: Int) -> DayClip? {
        clips.indices.contains(index) ? clips[index] : nil
    }

    func isMine(at index: Int) -> Bool {
        clip(at: index).map { Self.isMine($0, myID: myID) } ?? false
    }

    func index(ofDay day: Int, authorID: String?) -> Int? {
        clips.firstIndex { clip in
            guard clip.day == day else { return false }
            guard let authorID,
                  authorID != RoomProgress.soloAuthorID,
                  authorID != myID
            else { return Self.isMine(clip, myID: myID) }
            return clip.authorID == authorID
        }
    }

    func index(ofDay day: Int, authorID: String?, takeID: UUID?) -> Int? {
        guard let person = index(ofDay: day, authorID: authorID) else {
            return clips.firstIndex { $0.day == day }
        }
        let author = clips[person].authorID
        return clips.indices.first {
            clips[$0].day == day && clips[$0].authorID == author && clips[$0].takeID == takeID
        } ?? person
    }

    struct Position: Equatable {
        let day: Int
        let momentCount: Int
        let label: String?
        let authorName: String?
    }

    func position(at index: Int) -> Position? {
        guard let clip = clip(at: index) else { return nil }
        return Position(
            day: clip.day,
            momentCount: storyMomentCount,
            label: clip.label,
            authorName: Self.isMine(clip, myID: myID) ? nil : clip.authorName)
    }
}
