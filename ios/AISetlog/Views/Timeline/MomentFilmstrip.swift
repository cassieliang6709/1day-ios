import SwiftUI

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

    private var nextOpen: Int? { agenda.suggested }

    private func shown(_ slot: Int) -> DayClip? {
        let slotClips = clips.filter { $0.day == slot }
        return StoryGridView.mineAmong(slotClips, myID: myID) ?? slotClips.first
    }

    private var rows: [Int] {
        let filmed = slots.filter { shown($0) != nil }
            .sorted { a, b in
                let ta = shown(a)?.recordedAt ?? .distantFuture
                let tb = shown(b)?.recordedAt ?? .distantFuture
                return ta != tb ? ta < tb : a < b
            }
        return filmed + slots.filter { shown($0) == nil }
    }

    var body: some View {
        let rows = rows
        let filmedCount = rows.filter { shown($0) != nil }.count
        VStack(alignment: .leading, spacing: 0) {
            if let next = nextOpen {
                filmButton(next, anyFilmed: filmedCount > 0)
                    .padding(.bottom, 20)
            }
            ForEach(Array(rows.enumerated()), id: \.element) { index, slot in
                row(slot, index: index, count: rows.count, filmedCount: filmedCount)
            }
        }
    }


    private func filmButton(_ slot: Int, anyFilmed: Bool) -> some View {
        Button { onFilm(slot) } label: {
            Label(buttonTitle(for: slot, anyFilmed: anyFilmed), systemImage: "camera.fill")
                .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.onBrand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    OneDay.brandHorizontal,
                    in: RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous))
                .oneDayGlow(strength: 0.7)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filmstrip-cta")
    }

    private func buttonTitle(for slot: Int, anyFilmed: Bool) -> String {
        guard challenge.isTimeOnly else {
            return Strings.filmNamedMoment(presenter.title(forSlot: slot))
        }
        return anyFilmed ? Strings.filmNextMoment : Strings.captureThisMoment
    }


    @ViewBuilder
    private func row(_ slot: Int, index: Int, count: Int, filmedCount: Int) -> some View {
        let clip = shown(slot)
        DiaryTimelineRow(
            time: clip.flatMap { schedule.railLabel(forSlot: slot, recordedAt: $0.recordedAt) },
            isFirst: index == 0,
            isLast: index == count - 1,
            filmed: clip != nil,
            highlighted: slot == nextOpen,
            railReached: index < filmedCount - 1
        ) {
            if let clip {
                filmedContent(slot, clip: clip)
            } else {
                emptyContent(slot, isNext: slot == nextOpen)
            }
        }
    }

    private static let thumbWidth: CGFloat = 112
    private static let thumbHeight: CGFloat = 150

    private func filmedContent(_ slot: Int, clip: DayClip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { onPlay(slot) } label: { thumbnail(clip) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(accessibilityTitle(slot, clip: clip)))
                .accessibilityIdentifier("diary-play-\(slot)")

            VStack(alignment: .leading, spacing: 8) {
                captionText(slot, clip: clip)
                if challenge.isShared, agenda.isAwaitingMine(slot: slot) {
                    addYoursButton(slot)
                }
            }
            .padding(.top, 4)
        }
    }

    private func thumbnail(_ clip: DayClip) -> some View {
        ClipTile(url: clip.url, refreshToken: clip.recordedAt)
            .frame(width: Self.thumbWidth, height: Self.thumbHeight)
            .overlay(alignment: .bottomTrailing) {
                if let emoji = clip.emoji.first {
                    Text(emoji).font(.system(size: 18)).padding(OneDay.Space.s)
                }
            }
    }

    @ViewBuilder
    private func captionText(_ slot: Int, clip: DayClip) -> some View {
        if let text = clip.overlayText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .lineLimit(4)
        } else if !challenge.isTimeOnly {
            Text(presenter.title(forSlot: slot))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
        }
        if let date = schedule.railCaption(forSlot: slot, recordedAt: clip.recordedAt) {
            Text(date)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.inkFaint)
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
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filmstrip-add-yours-\(slot)")
    }

    private func emptyContent(_ slot: Int, isNext: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button { onFilm(slot) } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                if isNext { Text(Strings.filmThisOne) }
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(isNext ? OneDay.brandText : OneDay.inkFaint)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(shape.fill(isNext
                ? AnyShapeStyle(Color.oneDayBrand.opacity(0.07))
                : AnyShapeStyle(OneDay.surfaceSoft.opacity(0.5))))
            .overlay(shape.strokeBorder(
                isNext ? Color.oneDayBrand : OneDay.inkFaint.opacity(0.45),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Strings.notYetFilmed))
        .accessibilityValue(Text(Strings.slotPosition(slot, of: agenda.total)))
        .accessibilityHint(Text(Strings.filmThisOne))
        .accessibilityIdentifier("diary-film-\(slot)")
    }

    private func accessibilityTitle(_ slot: Int, clip: DayClip) -> String {
        let time = schedule.railLabel(forSlot: slot, recordedAt: clip.recordedAt)
        let caption = clip.overlayText
        return [time, caption].compactMap { $0 }.joined(separator: ", ")
    }
}
