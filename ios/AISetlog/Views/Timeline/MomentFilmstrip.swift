import SwiftUI

/// The day as a diary, for a story with no prompts (按时间).
///
/// One row per clip, top to bottom in the order they were filmed: the time on
/// the left in big digits, a dot on a thin rail, and the clip itself on the
/// right with its caption. The moments not filmed yet follow as dashed rows,
/// and the main button above the list opens the next one.
///
/// A 按时间 story's slots have no names — only 「第 N 个瞬间」, the numbering
/// 1.3 deleted — so the time a clip was taken is the row's heading. It is the
/// only real fact this kind of story has about its moments, and the reason
/// somebody picked 按时间.
///
/// (This used to be a horizontal strip of 78pt cells; the name stayed so the
/// story page's call site didn't change.)
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

    /// The slot the big button opens: the earliest one nobody has filmed, or
    /// nil once the day is full.
    private var nextOpen: Int? { agenda.suggested }

    /// The clip a slot shows: mine if I filmed it, else whoever did.
    private func shown(_ slot: Int) -> DayClip? {
        let slotClips = clips.filter { $0.day == slot }
        return StoryGridView.mineAmong(slotClips, myID: myID) ?? slotClips.first
    }

    /// Filmed slots in filming order, then the open ones in plan order.
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

    // MARK: - The button

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

    /// Nothing filmed yet: 拍下这一刻. After that: 拍下一段. A story that does
    /// have prompts names the one it is about to open.
    private func buttonTitle(for slot: Int, anyFilmed: Bool) -> String {
        guard challenge.isTimeOnly else {
            return Strings.filmNamedMoment(presenter.title(forSlot: slot))
        }
        return anyFilmed ? Strings.filmNextMoment : Strings.captureThisMoment
    }

    // MARK: - One row

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
        Color.clear
            .frame(width: Self.thumbWidth, height: Self.thumbHeight)
            .overlay { ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if let emoji = clip.emoji.first {
                    Text(emoji).font(.system(size: 18)).padding(6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OneDay.hairline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The clip's own caption if it has one; a 7-day story's date under it.
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

    /// A moment not filmed yet: a dashed placeholder the height of one line.
    /// The next one is in brand colour and says 开拍; the rest are a plus,
    /// because a story you can film out of order should not make them look
    /// unavailable.
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
        // Every empty row is 「还没拍」, so without a position VoiceOver reads
        // several identical buttons in a row.
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
