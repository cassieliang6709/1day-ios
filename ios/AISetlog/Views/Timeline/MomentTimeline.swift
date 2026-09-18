import SwiftUI

/// The day as one vertical timeline: every moment in order, on one rail,
/// whether it has been filmed or not.
///
/// This replaces two lists and their two headings. The page used to be
/// 「还没拍的」 — a glass card of rows — then 「拍过的」 — a three-column contact
/// sheet — which meant the order of your day was cut in half and re-sorted by
/// state, twice. A moment that was second in the plan and filmed appeared below
/// a moment that was fifth and empty, and the only way to know either one's
/// position was the words 第一个瞬间 / 第二个瞬间 that 1.3 deletes.
///
/// So: one rail, day order, and the state is carried by the node instead of by
/// a section. Filled dot and a still = filmed. Hollow dot and 开拍 = yours to
/// take. A ring = the one worth starting with. Nothing here is numbered, and
/// nothing needs to be: the rail *is* the ordinal.
///
/// It is deliberately not a `LazyVStack`. The rail's drawn progress has to know
/// where the last filmed node is, which means measuring all of them, and a
/// day is three to seven rows.
struct MomentTimeline: View {
    let challenge: Challenge
    let clips: [DayClip]
    let members: [(id: String, name: String)]
    let myID: String
    let agenda: StoryAgenda
    /// A filmed moment was tapped — play it.
    let onPlay: (Int) -> Void
    /// An open moment was tapped — film it.
    let onFilm: (Int) -> Void

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }
    private var schedule: StorySchedule { StorySchedule(challenge) }

    /// Every slot in the plan, in order. The agenda's two lists are about state;
    /// this is about the day.
    private var slots: [Int] {
        agenda.total > 0 ? Array(1...agenda.total) : []
    }

    /// How far down the rail to paint brand colour: to the last filmed node.
    ///
    /// Counted from the *last* one rather than from the count, because a day
    /// filmed out of order — which 1.2 made possible on purpose — has holes in
    /// it, and a rail that stopped at "three filmed" would stop above a still
    /// that is plainly there.
    private var filledThrough: Int {
        agenda.filmed.last ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(slots, id: \.self) { slot in
                node(slot)
            }
        }
    }

    // MARK: - The rail

    /// One node's slice of the rail: a full-height line with the dot on it.
    ///
    /// Full height, one colour per node, is the whole trick. Drawn behind the
    /// stack instead, the painted length could only ever be a fraction of the
    /// total — and the nodes are not the same height, because a filmed one
    /// carries a still — so at 1 filmed of 3 the progress line ended in the
    /// middle of the first thumbnail. Per node, the colour change lands exactly
    /// on a node boundary, which is the only place it means anything.
    ///
    /// Brand runs through the last filmed node. `filledThrough` is the last
    /// filmed *slot* rather than the count, because a day filmed out of order
    /// has holes in it and a line that stopped after "three filmed" would stop
    /// above a still that is plainly there.
    private func railColumn(_ slot: Int, filmed: Bool, suggested: Bool) -> some View {
        let reached = slot <= filledThrough
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(reached
                    ? AnyShapeStyle(Color.oneDayBrand)
                    // Not `surfaceSoft`: #DCEBFF on the #F5F8FF canvas is a
                    // line you cannot see, and an invisible rail leaves three
                    // dots floating in space.
                    : AnyShapeStyle(OneDay.inkFaint.opacity(0.38)))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                // Starts at the first dot and stops at the last: a rail running
                // past either end reads as a day with moments off-screen.
                .padding(.top, slot == slots.first ? 11 : 0)
                .padding(.bottom, slot == slots.last ? 0 : 0)

            dot(filmed: filmed, suggested: suggested)
                // Level with the first line of text beside it, not with the top
                // of the node: a filmed node's still would drag it up.
                .padding(.top, 6)
        }
        .padding(.leading, Self.dotColumn)
        .allowsHitTesting(false)
    }

    /// Where the dots sit, and therefore how far the content is indented.
    private static let dotColumn: CGFloat = 5
    private static let contentInset: CGFloat = 26

    // MARK: - One moment

    @ViewBuilder
    private func node(_ slot: Int) -> some View {
        let slotClips = clips.filter { $0.day == slot }
        let isFilmed = !slotClips.isEmpty
        let isSuggested = agenda.isSuggested(slot: slot)

        HStack(alignment: .top, spacing: 0) {
            railColumn(slot, filmed: isFilmed, suggested: isSuggested)
                .frame(width: Self.contentInset, alignment: .leading)

            if isFilmed {
                filmedNode(slot, slotClips: slotClips)
            } else {
                openNode(slot, isSuggested: isSuggested)
            }
        }
        .padding(.vertical, 7)
    }

    private func dot(filmed: Bool, suggested: Bool) -> some View {
        Circle()
            .fill(filmed ? Color.oneDayBrand : OneDay.surface)
            .frame(width: 11, height: 11)
            .overlay {
                Circle().strokeBorder(
                    filmed || suggested ? Color.oneDayBrand : OneDay.surfaceSoft,
                    lineWidth: 2)
            }
            // Only the suggestion gets a halo, and only while it is still a
            // suggestion — `StoryAgenda.suggested` is nil once the day is full.
            .background {
                if suggested {
                    Circle()
                        .fill(Color.oneDayBrand.opacity(0.16))
                        .frame(width: 21, height: 21)
                }
            }
            // Centred on the rail: the line is 2pt at `dotColumn`, the dot is
            // 11pt, so it sits 4.5pt to the left of where the line starts.
            .padding(.leading, -4.5)
            .accessibilityHidden(true)
    }

    /// A moment that happened. The title reads back in `inkSoft`, because the
    /// still under it is the content and the row is a record rather than an
    /// invitation.
    private func filmedNode(_ slot: Int, slotClips: [DayClip]) -> some View {
        let mine = StoryGridView.mineAmong(slotClips, myID: myID)
        let lanes = StoryGridView.lanes(slotClips: slotClips, members: members, myID: myID)
        let shown = mine ?? slotClips.first

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title(for: slot))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                if let stamp = schedule.railLabel(
                    forSlot: slot, recordedAt: shown?.recordedAt) {
                    Text(stamp)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                        .monospacedDigit()
                }
            }

            ClipThumb(
                momentTitle: title(for: slot),
                lanes: lanes,
                // The time is on the line above, where it lines up with every
                // other node's. Repeating it on the still puts the same number
                // twice in one row.
                timeStamp: nil,
                authorNames: challenge.isShared ? lanes.compactMap(\.authorName) : [],
                reaction: shown?.emoji.first,
                awaitingMine: mine == nil,
                // Wide and short. This is a row in a list, not a cell in a
                // contact sheet: it has the full width and no neighbour to
                // match, so a portrait tile here would push the next moment
                // most of a screen away.
                aspectRatio: 2.1,
                sourceAspect: challenge.resolvedOrientation == .landscape
                    ? 16.0 / 9 : 9.0 / 16
            ) {
                onPlay(slot)
            }
        }
    }

    /// A moment still to take. Reuses the row the 「还没拍的」 card was built
    /// from, minus its own card: the rail is the container now.
    private func openNode(_ slot: Int, isSuggested: Bool) -> some View {
        OpenSlotRow(
            momentTitle: title(for: slot),
            momentIcon: icon(for: slot),
            awaitingMine: agenda.isAwaitingMine(slot: slot),
            isSuggested: isSuggested
        ) {
            onFilm(slot)
        }
        .glassSurface(radius: OneDay.Radius.card)
    }

    // MARK: - Copy

    /// A time-only story has no prompt to show, so the slot's own label stands
    /// in. That label is 「第 N 个瞬间」 — the one place in the app where a
    /// numbered moment is still the honest answer, because the story genuinely
    /// has nothing else to call it.
    private func title(for slot: Int) -> String {
        challenge.isTimeOnly
            ? Strings.lockedSlot(oneDay: challenge.isOneDay, day: slot)
            : presenter.title(forSlot: slot)
    }

    private func icon(for slot: Int) -> String {
        challenge.isTimeOnly
            ? "camera.fill"
            : MomentCatalog.icon(for: challenge.momentValue(forSlot: slot))
    }
}
