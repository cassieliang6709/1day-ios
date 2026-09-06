import SwiftUI

/// The story so far: a dense 3-column contact sheet of the moments that exist.
///
/// It used to hold every slot, filmed or not, at the same size and weight —
/// which made "what's left" and "what happened" the same picture. Empty slots
/// have moved out to the next-up card and the quiet list, so this sheet is
/// only ever a record of the day.

/// Which layout the story is being read in. Persisted, so the choice sticks
/// across stories and launches.
enum StoryViewMode: String, CaseIterable {
    case timeline, grid

    static let storageKey = "story.viewMode"

    var icon: String {
        switch self {
        case .timeline: "list.bullet.indent"
        case .grid: "square.grid.3x3.fill"
        }
    }
}

/// Two icon segments. Deliberately unlabelled — it sits next to the story's
/// stats and shouldn't compete with them for reading.
struct ViewModeToggle: View {
    @Binding var mode: StoryViewMode
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StoryViewMode.allCases, id: \.self) { option in
                let isOn = option == mode
                Button {
                    withAnimation(OneDay.Motion.snap) { mode = option }
                } label: {
                    Image(systemName: option.icon)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(isOn ? .white : OneDay.inkFaint)
                        .frame(width: 34, height: 27)
                        .background {
                            if isOn {
                                Capsule()
                                    .fill(Color.oneDayBlue)
                                    .matchedGeometryEffect(id: "viewmode", in: indicator)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    option == .timeline ? Strings.viewTimeline : Strings.viewGrid)
            }
        }
        .padding(3)
        .background(OneDay.surfaceSoft.opacity(0.85), in: Capsule())
        .sensoryFeedback(.selection, trigger: mode)
    }
}

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
            aspectRatio: challenge.resolvedOrientation == .landscape ? 1.43 : 0.72
        ) {
            onTap(slot)
        }
    }
}
