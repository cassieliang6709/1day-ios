import SwiftUI

/// The day as one horizontal strip of frames — for a story with no prompts.
///
/// `MomentTimeline` is the vertical rail every other story uses, and it is the
/// better shape when each moment has a name: a name wants a line to itself, and
/// a rail keeps seven of them readable. A 按时间 story has no names. Its slots
/// are 「第 1 个瞬间」, 「第 2 个瞬间」 — which is exactly the numbering 1.3
/// deleted everywhere else — so a vertical list of them is a list of nothing,
/// one nothing per line.
///
/// A strip says the same thing with pictures: what you shot, in order, plus the
/// gaps. The label under a filmed cell is the *time* it was taken, which is the
/// only real fact this kind of story has about its own moments and the reason
/// somebody chose 按时间 in the first place.
struct MomentFilmstrip: View {
    let challenge: Challenge
    let clips: [DayClip]
    let members: [(id: String, name: String)]
    let myID: String
    let agenda: StoryAgenda
    let onPlay: (Int) -> Void
    let onFilm: (Int) -> Void

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var schedule: StorySchedule { StorySchedule(challenge) }
    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    private var slots: [Int] { agenda.total > 0 ? Array(1...agenda.total) : [] }

    /// The cell a tap on the big button opens: the earliest one nobody has
    /// filmed, or nil once the day is full.
    private var nextOpen: Int? { agenda.suggested }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Horizontal, and it scrolls: a seven-slot story is seven 78pt
            // cells against a 350pt content width, so three of them are off
            // screen by design rather than squeezed.
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 9) {
                    ForEach(slots, id: \.self) { cell($0) }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            // One segment per slot. The thin bar on the page above is about the
            // whole story; this is about which *cells* you are looking at, and
            // it lines up with them.
            HStack(spacing: 4) {
                ForEach(slots, id: \.self) { slot in
                    Capsule()
                        .fill(agenda.filmed.contains(slot)
                            ? AnyShapeStyle(OneDay.brandHorizontal)
                            : AnyShapeStyle(OneDay.surfaceSoft))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)

            if let next = nextOpen {
                Button { onFilm(next) } label: {
                    Text(buttonTitle(for: next))
                        .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            OneDay.brandHorizontal,
                            in: RoundedRectangle(
                                cornerRadius: OneDay.Radius.card, style: .continuous))
                        .oneDayGlow(strength: 0.7)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("filmstrip-cta")
            }
        }
    }

    /// A story with no prompts cannot say what to film, so the button names the
    /// act instead. One that does have them says which.
    private func buttonTitle(for slot: Int) -> String {
        challenge.isTimeOnly
            ? Strings.captureThisMoment
            : Strings.filmNamedMoment(presenter.title(forSlot: slot))
    }

    // MARK: - One cell

    @ViewBuilder
    private func cell(_ slot: Int) -> some View {
        let slotClips = clips.filter { $0.day == slot }
        let isFilmed = !slotClips.isEmpty
        let isNext = slot == nextOpen

        VStack(spacing: 6) {
            if isFilmed {
                filmedCell(slot, slotClips: slotClips)
            } else {
                emptyCell(slot, isNext: isNext)
            }

            // Only under a filmed cell. A brand-new 按时间 story has nothing
            // in any slot, and 「还没拍」 five times in a row is exactly the
            // repeated copy 1.3 spent its time deleting — the cell itself
            // already says 开拍 or draws a plus.
            Text(isFilmed ? label(for: slot, slotClips: slotClips) : " ")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: Self.cellWidth)
        }
    }

    private static let cellWidth: CGFloat = 78
    private static let cellHeight: CGFloat = 104

    private func filmedCell(_ slot: Int, slotClips: [DayClip]) -> some View {
        let mine = StoryGridView.mineAmong(slotClips, myID: myID)
        let lanes = StoryGridView.lanes(slotClips: slotClips, members: members, myID: myID)

        return ClipThumb(
            momentTitle: label(for: slot, slotClips: slotClips),
            lanes: lanes,
            // The time is the cell's own label, directly underneath. On the
            // thumbnail too it would be the same number twice in 104 points.
            timeStamp: nil,
            authorNames: challenge.isShared ? lanes.compactMap(\.authorName) : [],
            reaction: (mine ?? slotClips.first)?.emoji.first,
            awaitingMine: mine == nil,
            aspectRatio: Self.cellWidth / Self.cellHeight,
            sourceAspect: challenge.resolvedOrientation == .landscape ? 16.0 / 9 : 9.0 / 16
        ) {
            onPlay(slot)
        }
        .frame(width: Self.cellWidth, height: Self.cellHeight)
    }

    /// A gap. The next one is a dashed brand outline saying 开拍; the ones after
    /// it are a plus, because a story you can film out of order should not make
    /// the fourth slot look unavailable.
    private func emptyCell(_ slot: Int, isNext: Bool) -> some View {
        Button { onFilm(slot) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isNext
                        ? AnyShapeStyle(Color.oneDayBrand.opacity(0.07))
                        : AnyShapeStyle(OneDay.surfaceSoft.opacity(0.7)))

                if isNext {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color.oneDayBrand,
                            style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    Text(Strings.filmThisOne)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.oneDayBrand)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(OneDay.inkFaint)
                }
            }
            .frame(width: Self.cellWidth, height: Self.cellHeight)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label(for: slot, slotClips: [])))
        .accessibilityHint(Text(Strings.filmThisOne))
    }

    /// The time it was taken. Only ever asked of a filmed cell for display;
    /// the empty-cell accessibility label uses the `notYetFilmed` fallback,
    /// because VoiceOver does need something to read and 「第 3 个瞬间」 — the
    /// numbering this release removed — is not it.
    private func label(for slot: Int, slotClips: [DayClip]) -> String {
        let shown = StoryGridView.mineAmong(slotClips, myID: myID) ?? slotClips.first
        if let stamp = schedule.railLabel(forSlot: slot, recordedAt: shown?.recordedAt) {
            return stamp
        }
        return challenge.isTimeOnly
            ? Strings.notYetFilmed
            : presenter.title(forSlot: slot)
    }
}
