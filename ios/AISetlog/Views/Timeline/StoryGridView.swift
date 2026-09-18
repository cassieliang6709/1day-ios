import SwiftUI

/// Lane maths for a moment with more than one person in it, plus the contact
/// sheet that used to be the story page's lower half.
///
/// `StoryGridView` itself has no call sites as of 1.3 — `MomentTimeline`
/// replaced the two-list page — but `lanes`, `rows` and `mineAmong` are the
/// only implementation of "who is in this moment, in the order the film stacks
/// them", and both the timeline and `ClipThumb` read them. They are static and
/// pure, and `GridTapTests` covers them.
///
/// The view is kept rather than deleted because the grid is still the right
/// shape for a finished story and 6.1 (下线片段左右滑) may want it back; it is
/// eleven lines that compile and nothing else depends on.

// MARK: - Grid

/// One person's place in a moment: their take, or the space held for it.
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
    /// Which slots to show, in day order. The page passes `StoryAgenda.filmed`
    /// — the sheet doesn't decide what counts as filmed.
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

    /// Filmed takes for this moment, in the order the tile stacks them.
    /// My take stays first when it exists; everyone else follows by name.
    /// Pending members are expressed by the room roster elsewhere rather than
    /// as empty video panes, so the tile matches what its preview can play.
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

    /// Splits lanes into rows for a grid of `columns`.
    static func rows(of lanes: [MomentLane], columns: Int) -> [[MomentLane]] {
        guard columns > 0 else { return [lanes] }
        return stride(from: 0, to: lanes.count, by: columns).map {
            Array(lanes[$0..<min($0 + columns, lanes.count)])
        }
    }

    /// One filmed moment. Exactly one tap region, and it means "play this" —
    /// the tile it replaces had three stacked on top of each other.
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
            // Only in a room. A tile stands for the whole moment with everyone
            // stacked in it, so the badge is everyone in it — and in a solo
            // story it would be my own name on every clip I own.
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
