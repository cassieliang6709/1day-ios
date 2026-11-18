import SwiftUI



struct MomentLane: Identifiable {
    let authorID: String
    let authorName: String?
    let clip: DayClip?
    let isMine: Bool

    var id: String { authorID }
}

struct StoryGridView: View {
    let challenge: Challenge
    let clips: [DayClip]
    let members: [(id: String, name: String)]
    let myID: String
    let slots: [Int]
    let onTap: (Int) -> Void

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }
    private var schedule: StorySchedule { StorySchedule(challenge) }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(slots, id: \.self) { slot in
                cell(for: slot)
            }
        }
    }

    static func mineAmong(_ slotClips: [DayClip], myID: String) -> DayClip? {
        slotClips.first { $0.authorID == myID || $0.authorID == "local" }
    }

    private static func isMe(_ authorID: String, myID: String) -> Bool {
        authorID == myID || authorID == "local"
    }

    static func lanes(
        slotClips: [DayClip],
        members: [(id: String, name: String)],
        myID: String
    ) -> [MomentLane] {
        var byAuthor: [String: DayClip] = [:]
        for clip in slotClips { byAuthor[clip.authorID ?? myID] = clip }

        var memberNames: [String: String] = [:]
        for member in members { memberNames[member.id] = member.name }
        return byAuthor.map { authorID, clip in
            MomentLane(
                authorID: authorID,
                authorName: clip.authorName ?? memberNames[authorID],
                clip: clip,
                isMine: isMe(authorID, myID: myID))
        }
        .sorted { lhs, rhs in
            if lhs.isMine != rhs.isMine { return lhs.isMine }
            let left = lhs.authorName ?? lhs.authorID
            let right = rhs.authorName ?? rhs.authorID
            return left == right ? lhs.authorID < rhs.authorID : left < right
        }
    }

    static func rows(of lanes: [MomentLane], columns: Int) -> [[MomentLane]] {
        guard columns > 0 else { return [lanes] }
        return stride(from: 0, to: lanes.count, by: columns).map {
            Array(lanes[$0..<min($0 + columns, lanes.count)])
        }
    }

    @ViewBuilder
    private func cell(for slot: Int) -> some View {
        let slotClips = clips.filter { $0.day == slot }
        let mine = Self.mineAmong(slotClips, myID: myID)
        let lanes = Self.lanes(slotClips: slotClips, members: members, myID: myID)
        let shown = mine ?? slotClips.first

        ClipThumb(
            momentTitle: challenge.isTimeOnly
                ? Strings.lockedSlot(oneDay: challenge.isOneDay, day: slot)
                : presenter.title(forSlot: slot),
            lanes: lanes,
            timeStamp: schedule.railLabel(forSlot: slot, recordedAt: shown?.recordedAt),
            authorNames: challenge.isShared ? lanes.compactMap(\.authorName) : [],
            reaction: shown?.emoji.first,
            awaitingMine: mine == nil && !slotClips.isEmpty,
            aspectRatio: challenge.resolvedOrientation == .landscape ? 1.43 : 0.72,
            sourceAspect: challenge.resolvedOrientation == .landscape ? 16.0 / 9 : 9.0 / 16
        ) {
            onTap(slot)
        }
    }
}
