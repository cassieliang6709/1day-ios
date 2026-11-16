import SwiftUI

struct GeneratingFilm: View {
    let challenge: Challenge
    let clips: [DayClip]
    let stage: Int
    var progress: Double? = nil
    var canContinueInBackground: Bool? = nil

    static let stepCount = 3

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var schedule: StorySchedule { StorySchedule(challenge) }
    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }

    private var mergedCount: Int {
        guard clips.count > 1 else { return 0 }
        let fraction = Double(stage + 1) / Double(Self.stepCount + 1)
        let paced = Int((Double(clips.count) * fraction).rounded())
        return min(max(paced, 1), clips.count - 1)
    }

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
        }
    }

    private var progressCard: some View {
        GlassCard(padding: 16, tint: .oneDayBrand) {
            HStack(spacing: 14) {
                OneDayBuddy(size: 46, isWorking: true)

                VStack(alignment: .leading, spacing: 9) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.oneDaySky.opacity(0.25))
                            Capsule()
                                .fill(OneDay.brandHorizontal)
                                .frame(
                                    width: proxy.size.width * (progress
                                        ?? Double(mergedCount) / Double(max(clips.count, 1))))
                        }
                    }
                    .frame(height: 7)
                    .animation(OneDay.Motion.soft, value: mergedCount)
                    if let progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(OneDay.inkSoft)
                    }
                    if let canContinueInBackground {
                        Text(canContinueInBackground ? Strings.filmMayContinueInBackground : Strings.filmKeepOpen)
                            .font(.caption)
                            .foregroundStyle(OneDay.inkSoft)
                    }
                }
            }
        }
    }

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

                    ClipTile(url: clip.url, refreshToken: clip.recordedAt)
                        .frame(width: 54, height: 40)

                    VStack(alignment: .leading, spacing: 1) {
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
