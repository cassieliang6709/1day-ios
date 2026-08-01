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
    /// 0…3 — which named step the stitcher is on.
    let stage: Int

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var schedule: StorySchedule { StorySchedule(challenge) }
    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    /// How many moments the progress card shows as folded in. Paced off the
    /// stage so the count moves while the stitcher is quiet.
    private var mergedCount: Int {
        guard !clips.isEmpty else { return 0 }
        let fraction = Double(stage + 1) / 4
        return max(1, Int((Double(clips.count) * fraction).rounded()))
    }

    private var steps: [(text: String, icon: String)] {
        var list: [(String, String)] = [(Strings.stepCollecting, "square.stack.3d.up.fill")]
        if challenge.isShared {
            list.append((Strings.stepSyncing, "person.2.fill"))
        }
        list.append((Strings.stepTransitions, "wand.and.sparkles"))
        list.append((Strings.stepFinishing, "film.fill"))
        return list
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
        GlassCard(padding: 16, tint: .oneDayBlue) {
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
                            ? Color.oneDayBlue : Color.oneDaySky.opacity(0.45))
                        .contentTransition(.symbolEffect(.replace))

                    Text(schedule.railLabel(forSlot: clip.day))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(OneDay.inkFaint)
                        .lineLimit(1)
                        .frame(width: 68, alignment: .leading)

                    ClipThumbnail(url: clip.url, refreshToken: clip.recordedAt)
                        .frame(width: 54, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(clip.label ?? presenter.title(forSlot: clip.day))
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
    private var careNote: some View {
        GlassCard(padding: 16, tint: .oneDayLavender) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.oneDayLavender)
                    Text(Strings.stitchingCare)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                }

                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 9) {
                        Image(systemName: index <= stage ? "checkmark.circle.fill" : step.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(index <= stage ? Color.oneDayMint : OneDay.inkFaint)
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

                Text(Strings.stitchingCareBody)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .padding(.top, 2)
            }
        }
    }
}
