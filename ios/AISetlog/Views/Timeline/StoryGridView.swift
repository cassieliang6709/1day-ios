import SwiftUI

/// The other way to look at a story: a dense 3-column contact sheet.
///
/// The timeline answers "how did the day go"; the grid answers "what have I
/// got". A whole story fits on one screen, which is the right shape when
/// you're checking what's left rather than reading the day back.

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
    let onTapFilmed: (Int, String?) -> Void
    let onTapEmpty: (Int) -> Void

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }
    private var schedule: StorySchedule { StorySchedule(challenge) }
    private var nextSlot: Int? { challenge.cards.first { $0.clipFileName == nil }?.day }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
        ) {
            ForEach(challenge.cards) { card in
                cell(for: card)
            }
        }
        .padding(.horizontal, 20)
    }

    /// What tapping a tile should do.
    ///
    /// The grid used to open the viewer whenever *anyone* had filmed the slot,
    /// so a moment a friend had already filmed became unreachable — there was
    /// no way left to add your own take. The timeline never had that problem
    /// because it asks "have *I* filmed this", and so does this.
    enum Tap: Equatable {
        case preview(authorID: String?)
        case record
    }

    static func tap(slotClips: [DayClip], myID: String) -> Tap {
        if let mine = mineAmong(slotClips, myID: myID) {
            return .preview(authorID: mine.authorID)
        }
        return .record
    }

    static func mineAmong(_ slotClips: [DayClip], myID: String) -> DayClip? {
        slotClips.first { $0.authorID == myID || $0.authorID == "local" }
    }

    private static func isMe(_ authorID: String, myID: String) -> Bool {
        authorID == myID || authorID == "local"
    }

    /// Who shares this moment, in the order the tile stacks them.
    ///
    /// Me first: my own lane is the one I need to find and tap, so it shouldn't
    /// move as friends' clips arrive. Everyone else follows by name, which
    /// keeps the rest stable too. Seats come from the room's roster, so a
    /// friend who has filmed nothing yet still holds a place — that's the
    /// point of showing the moment rather than just its footage.
    static func lanes(
        slotClips: [DayClip],
        members: [(id: String, name: String)],
        myID: String
    ) -> [MomentLane] {
        var byAuthor: [String: DayClip] = [:]
        for clip in slotClips { byAuthor[clip.authorID ?? myID] = clip }

        var seats: [(id: String, name: String?)] = members.map { ($0.id, $0.name) }
        // Footage always earns a lane, even if its author somehow isn't in the
        // roster — dropping a clip from the tile would be the worse failure.
        let known = Set(seats.map(\.id))
        for (id, clip) in byAuthor where !known.contains(id) {
            seats.append((id, clip.authorName))
        }
        if seats.isEmpty { seats = [(myID, nil)] }

        let mine = seats.filter { isMe($0.id, myID: myID) }
        let others = seats
            .filter { !isMe($0.id, myID: myID) }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }

        return (mine + others).map { seat in
            MomentLane(
                authorID: seat.id, authorName: seat.name,
                clip: byAuthor[seat.id], isMine: isMe(seat.id, myID: myID))
        }
    }

    /// Splits lanes into rows for a grid of `columns`.
    static func rows(of lanes: [MomentLane], columns: Int) -> [[MomentLane]] {
        guard columns > 0 else { return [lanes] }
        return stride(from: 0, to: lanes.count, by: columns).map {
            Array(lanes[$0..<min($0 + columns, lanes.count)])
        }
    }

    @ViewBuilder
    private func cell(for card: DayCard) -> some View {
        let slotClips = clips.filter { $0.day == card.day }
        let mine = Self.mineAmong(slotClips, myID: myID)
        let awaitingMine = mine == nil && !slotClips.isEmpty
        // A moment nobody has filmed keeps the plain empty tile. Held places
        // only say something once there's a take to hold them against;
        // otherwise every untouched slot turns into a stack of blanks.
        let lanes = slotClips.isEmpty
            ? []
            : Self.lanes(slotClips: slotClips, members: members, myID: myID)

        StoryGridCell(
            momentTitle: presenter.title(forSlot: card.day),
            momentIcon: MomentCatalog.icon(for: challenge.momentValue(forSlot: card.day)),
            lanes: lanes,
            timeStamp: schedule.railLabel(
                forSlot: card.day, recordedAt: (mine ?? slotClips.first)?.recordedAt),
            reactions: (mine ?? slotClips.first)?.emoji ?? [],
            isNext: card.day == nextSlot,
            awaitingMine: awaitingMine,
            aspectRatio: challenge.resolvedOrientation == .landscape ? 1.43 : 0.72
        ) {
            switch Self.tap(slotClips: slotClips, myID: myID) {
            case .preview(let authorID): onTapFilmed(card.day, authorID)
            case .record: onTapEmpty(card.day)
            }
        }
    }
}

/// One tile. Built as a fixed `Color.clear` box with edge-pinned overlays:
/// overlays never resize their base, so nothing can push past the tile's clip
/// frame the way a filling VStack does.
struct StoryGridCell: View {
    let momentTitle: String
    let momentIcon: String
    /// Everyone sharing this moment, in stacking order. Empty means nobody has
    /// filmed it — the tile falls back to its plain empty state.
    var lanes: [MomentLane] = []
    var timeStamp: String?
    var reactions: [String] = []
    var isNext = false
    /// A friend filmed this moment and I haven't — the tile shows their take
    /// but is still an invitation to film mine.
    var awaitingMine = false
    var aspectRatio: CGFloat = 0.72
    let onTap: () -> Void

    private let radius: CGFloat = 16

    private var isFilled: Bool { lanes.contains { $0.clip != nil } }

    /// Same row/column split the finished film uses, so the tile is a real
    /// preview of the moment rather than a lookalike.
    private var grid: (rows: Int, columns: Int) {
        VideoStitcher.grid(for: lanes.count, in: CGSize(width: 100, height: 140))
    }

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { background.clipped() }
            .overlay(alignment: .topLeading) { topLeading }
            .overlay(alignment: .topTrailing) { topTrailing }
            .overlay(alignment: .bottom) { caption }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay { border }
            .oneDaySoftShadow(strength: isFilled ? 0.7 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture(perform: onTap)
            .animation(OneDay.Motion.soft, value: lanes.map(\.id).joined())
    }

    @ViewBuilder
    private var background: some View {
        if isFilled {
            let split = grid
            VStack(spacing: 1) {
                ForEach(Array(StoryGridView.rows(of: lanes, columns: split.columns).enumerated()),
                        id: \.offset) { _, row in
                    HStack(spacing: 1) {
                        ForEach(row) { lane in laneView(lane) }
                    }
                }
            }
        } else {
            (isNext ? Color.oneDayBlue.opacity(0.07) : OneDay.surfaceSoft.opacity(0.4))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: momentIcon)
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(isNext ? Color.oneDayBlue : Color.oneDaySky)
                            .symbolEffect(.pulse, isActive: isNext)
                        Text(momentTitle)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(isNext ? OneDay.ink : OneDay.inkSoft)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 8)
                    }
                }
        }
    }

    /// One person's band: their frame, or the place kept for it.
    @ViewBuilder
    private func laneView(_ lane: MomentLane) -> some View {
        if let clip = lane.clip {
            ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            // Mine reads as an invitation; a friend's reads as waiting.
            (lane.isMine ? Color.oneDayBlue.opacity(0.12) : OneDay.surfaceSoft.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if lane.isMine {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.oneDayBlue)
                    } else {
                        AvatarDot(name: lane.authorName, size: 22, isPending: true)
                    }
                }
        }
    }

    @ViewBuilder
    private var topLeading: some View {
        if let timeStamp {
            Text(timeStamp)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
        }
    }

    @ViewBuilder
    private var topTrailing: some View {
        if isFilled {
            HStack(spacing: 3) {
                Image(systemName: awaitingMine ? "camera.circle.fill" : "play.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(awaitingMine ? Color.oneDayBlue : .white.opacity(0.92))
                    .shadow(radius: 3)
            }
            .padding(6)
        }
    }

    /// Only filmed tiles get a caption bar — an empty tile already shows its
    /// moment name in the centre, and two labels in one tile is noise.
    @ViewBuilder
    private var caption: some View {
        if isFilled {
            HStack(spacing: 4) {
                Text(momentTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if let first = reactions.first {
                    Text(first).font(.system(size: 10))
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.62)],
                    startPoint: .top, endPoint: .bottom))
        }
    }

    @ViewBuilder
    private var border: some View {
        if isNext, !isFilled {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(OneDay.brand, lineWidth: 2)
        } else if awaitingMine {
            // A friend's take is in there but mine isn't — the dashed edge says
            // the tile is still open to me.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    Color.oneDayBlue.opacity(0.65),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        } else if !isFilled {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    Color.oneDaySky.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(OneDay.hairline, lineWidth: 1)
        }
    }
}
