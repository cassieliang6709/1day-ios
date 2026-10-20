import SwiftUI

/// Screen 5 — the film being assembled.
///
/// The wait is short but it's the emotional peak, so it gets a screen rather
/// than a spinner: the mascot working, a checklist of what's happening, and
/// your own moments ticking over from pending to merged. The user watches
/// their day being folded together.
struct GeneratingFilm: View {
    let challenge: Challenge
    let clips: [DayClip]
    /// 0…`stepCount - 1` — which named step the stitcher is on.
    let stage: Int

    /// How many named steps there are. `FilmView` paces its ticker off this.
    static let stepCount = 3

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var schedule: StorySchedule { StorySchedule(challenge) }
    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    /// How many moments the progress card shows as folded in. Paced off the
    /// stage so the count moves while the stitcher is quiet — and capped one
    /// short of all of them. This screen is only on while there is no film
    /// yet, so "7/7 merged" here was always a claim the export hadn't backed:
    /// it used to read full about two seconds in, over a minute-long export.
    /// The last one lands when the film does, by the screen going away.
    private var mergedCount: Int {
        guard clips.count > 1 else { return 0 }
        let fraction = Double(stage + 1) / Double(Self.stepCount + 1)
        let paced = Int((Double(clips.count) * fraction).rounded())
        return min(max(paced, 1), clips.count - 1)
    }

    /// What the stitcher actually does, in order. There used to be a
    /// 「同步大家的片段」 step for rooms, but nothing syncs here — the clips
    /// are whatever the story page already had — so it was a tick for work
    /// that never ran.
    private var steps: [(text: String, icon: String)] {
        [
            (Strings.stepCollecting, "square.stack.3d.up.fill"),
            (Strings.stepTransitions, "wand.and.sparkles"),
            (Strings.stepFinishing, "film.fill"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                heading
                progressCard
                stepList
                careNote
            }
            .padding(.horizontal, 22)
            .padding(.top, 52)
            .padding(.bottom, OneDay.tabBarClearance + 24)
        }
        .scrollIndicators(.hidden)
    }

    private var heading: some View {
        VStack(spacing: 7) {
            Text(Strings.generatingTitle)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .multilineTextAlignment(.center)
            Text(Strings.generatingSubtitle)
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
        }
    }

    /// The mascot plus a bar — the one place in the app a progress bar earns
    /// its keep, because something genuinely is filling up.
    private var progressCard: some View {
        GlassCard(padding: 16, tint: .oneDayBrand) {
            HStack(spacing: 14) {
                OneDayBuddy(size: 46, isWorking: true)

                VStack(alignment: .leading, spacing: 9) {
                    Text(Strings.mergedProgress(mergedCount, total: max(clips.count, 1)))
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.ink)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.oneDaySky.opacity(0.25))
                            Capsule()
                                .fill(OneDay.brandHorizontal)
                                .frame(
                                    width: proxy.size.width
                                        * Double(mergedCount) / Double(max(clips.count, 1)))
                        }
                    }
                    .frame(height: 7)
                    .animation(OneDay.Motion.soft, value: mergedCount)
                }
            }
        }
    }

    /// Every moment in the film, ticking from pending to merged in order —
    /// the timeline from the previous screen, being consumed.
    private var stepList: some View {
        VStack(spacing: 0) {
            ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                HStack(spacing: 12) {
                    Image(systemName: index < mergedCount
                        ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(index < mergedCount
                            ? Color.oneDayBrand : Color.oneDaySky.opacity(0.45))
                        .contentTransition(.symbolEffect(.replace))

                    Text(schedule.railLabel(forSlot: clip.day, recordedAt: clip.recordedAt) ?? "")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(OneDay.inkFaint)
                        .lineLimit(1)
                        .frame(width: 68, alignment: .leading)

                    ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt)
                        .frame(width: 54, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        // A room names the moment or, with no name, says
                        // when it was filmed — never the 「第 N 天」 that
                        // `clip.label` falls back to (see `StorySchedule`).
                        Text(challenge.isShared && !challenge.isTimeOnly
                            ? (presenter.momentName(forSlot: clip.day)
                                ?? schedule.railCaption(forSlot: clip.day, recordedAt: clip.recordedAt)
                                ?? schedule.railLabel(forSlot: clip.day, recordedAt: clip.recordedAt)
                                ?? "")
                            : challenge.isTimeOnly
                            ? (schedule.railLabel(
                                forSlot: clip.day,
                                recordedAt: clip.recordedAt) ?? Strings.timeOnlyMoment)
                            : (clip.label ?? presenter.title(forSlot: clip.day)))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(OneDay.ink)
                            .lineLimit(1)
                        if let author = clip.authorName {
                            Text(author)
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundStyle(OneDay.inkSoft)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    Text(challenge.resolvedClipLength.secondsLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                }
                .padding(.vertical, 8)
                .opacity(index < mergedCount ? 1 : 0.5)
                .animation(OneDay.Motion.soft, value: mergedCount)

                if clip.id != clips.last?.id {
                    Divider().overlay(OneDay.hairline).padding(.leading, 29)
                }
            }
        }
        .padding(14)
        .glassSurface(radius: OneDay.Radius.card)
    }

    /// The named steps, so the wait says what it's doing.
    ///
    /// A step is ticked once the next one has started, never on its own: the
    /// current step — including the last, 导出, which is where the time
    /// actually goes — shows a spinner and its own icon until it's really
    /// behind us. The card's 「正在细心缝合 ✨」 heading and its line about
    /// "the right vibes" are gone; they described care the code doesn't take.
    private var careNote: some View {
        GlassCard(padding: 16, tint: .oneDayLavender) {
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    let done = index < stage
                    HStack(spacing: 9) {
                        Image(systemName: done ? "checkmark.circle.fill" : step.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(done ? Color.oneDayMint : OneDay.inkFaint)
                            .frame(width: 18)
                            .contentTransition(.symbolEffect(.replace))
                        Text(step.text)
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundStyle(index <= stage ? OneDay.ink : OneDay.inkSoft)
                        Spacer(minLength: 0)
                        if index == stage {
                            ProgressView().controlSize(.mini).tint(Color.oneDayLavender)
                        }
                    }
                    .animation(OneDay.Motion.soft, value: stage)
                }
            }
        }
    }
}
