import SwiftUI

struct MomentTimeline: View {
    let challenge: Challenge
    let clips: [DayClip]
    let members: [(id: String, name: String)]
    let myID: String
    let agenda: StoryAgenda
    let onPlay: (Int) -> Void
    let onFilm: (Int) -> Void

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }
    private var schedule: StorySchedule { StorySchedule(challenge) }

    private var slots: [Int] {
        agenda.total > 0 ? Array(1...agenda.total) : []
    }

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


    private func railColumn(_ slot: Int, filmed: Bool, suggested: Bool) -> some View {
        let reached = slot <= filledThrough
        return ZStack(alignment: .top) {
            Rectangle()
                .fill(reached
                    ? AnyShapeStyle(Color.oneDayBrand)
                    : AnyShapeStyle(OneDay.inkFaint.opacity(0.38)))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .padding(.top, slot == slots.first ? 11 : 0)
                .padding(.bottom, slot == slots.last ? 0 : 0)

            dot(filmed: filmed, suggested: suggested)
                .padding(.top, 6)
        }
        .padding(.leading, Self.dotColumn)
        .allowsHitTesting(false)
    }

    private static let dotColumn: CGFloat = 5
    private static let contentInset: CGFloat = 26


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
            .background {
                if suggested {
                    Circle()
                        .fill(Color.oneDayBrand.opacity(0.16))
                        .frame(width: 21, height: 21)
                }
            }
            .padding(.leading, -4.5)
            .accessibilityHidden(true)
    }

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

                if challenge.isShared, agenda.isAwaitingMine(slot: slot) {
                    addYoursButton(slot)
                }
            }

            ClipThumb(
                momentTitle: title(for: slot),
                lanes: lanes,
                timeStamp: nil,
                authorNames: challenge.isShared ? lanes.compactMap(\.authorName) : [],
                reaction: shown?.emoji.first,
                awaitingMine: mine == nil,
                aspectRatio: agenda.total > 7 ? 3.2 : 2.1,
                sourceAspect: challenge.resolvedOrientation == .landscape
                    ? 16.0 / 9 : 9.0 / 16,
                showsCaption: false
            ) {
                onPlay(slot)
            }
        }
    }

    private func addYoursButton(_ slot: Int) -> some View {
        Button { onFilm(slot) } label: {
            Label(Strings.addYourTake, systemImage: "plus")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.brandText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.oneDayMist.opacity(0.55), in: Capsule())
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .padding(.vertical, -8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Strings.addYourTake))
        .accessibilityHint(Text(title(for: slot)))
        .accessibilityIdentifier("timeline-add-yours-\(slot)")
    }

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
