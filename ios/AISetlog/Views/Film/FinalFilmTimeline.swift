import SwiftUI

/// Screen 6 — the finished film.
///
/// The stitched video plays at the top, and below it the same day runs down
/// the page as a scrollable timeline. That pairing is the point: the film is
/// the artefact you share, the timeline is the memory you scroll. Neither a
/// collage nor a grid — the day keeps its shape all the way to the end.
struct FinalFilmTimeline: View {
    let challenge: Challenge
    let clips: [DayClip]
    let filmURL: URL
    let isSaving: Bool
    let saveMessage: String?
    let onSave: () -> Void
    let onAdjust: () -> Void

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var schedule: StorySchedule { StorySchedule(challenge) }
    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }
    private var contributors: [String] {
        Array(Set(clips.compactMap(\.authorName))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                heading
                player
                actions
                facts
                timeline
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, OneDay.tabBarClearance + 24)
        }
        .scrollIndicators(.hidden)
    }

    private var heading: some View {
        VStack(spacing: 6) {
            Text(Strings.filmReadyTitle)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .multilineTextAlignment(.center)
            Text(Strings.filmReadyBody)
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
        }
    }

    private var player: some View {
        VlogPlayer(
            url: filmURL,
            aspectRatio: challenge.resolvedOrientation == .landscape ? 16 / 9 : 9 / 16)
            .frame(maxHeight: 460)
    }

    /// Save, share, adjust — three equal-weight actions, because at this point
    /// there's no single "correct" next step.
    private var actions: some View {
        HStack(spacing: 11) {
            FilmAction(
                icon: isSaving ? "arrow.down.circle" : "square.and.arrow.down",
                label: isSaving ? Strings.saving : Strings.saveAction,
                accent: .oneDayBlue,
                isBusy: isSaving,
                action: onSave)

            ShareLink(item: filmURL) {
                FilmActionLabel(
                    icon: "paperplane.fill",
                    label: Strings.shareAction,
                    accent: .oneDayLavender)
            }
            .buttonStyle(.plain)

            FilmAction(
                icon: "slider.horizontal.3",
                label: Strings.adjust,
                accent: .oneDayMint,
                action: onAdjust)
        }
        .overlay(alignment: .bottom) {
            if let saveMessage {
                Text(saveMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .padding(.top, 6)
                    .offset(y: 22)
                    .transition(.opacity)
            }
        }
        .animation(OneDay.Motion.soft, value: saveMessage)
    }

    /// Duration, moment count, people — the film's stats in one strip.
    private var facts: some View {
        HStack(spacing: 0) {
            fact(icon: "clock", title: Strings.durationLabel, value: schedule.filmDuration)
            divider
            fact(
                icon: "circle.grid.2x2.fill",
                title: Strings.momentsLabel,
                value: "\(clips.count)")
            divider
            fact(
                icon: "person.2.fill",
                title: Strings.peopleLabel,
                value: "\(max(contributors.count, 1))")
        }
        .padding(.vertical, 14)
        .glassSurface(radius: OneDay.Radius.card)
        .padding(.top, saveMessage == nil ? 0 : 18)
    }

    private var divider: some View {
        Rectangle()
            .fill(OneDay.hairline)
            .frame(width: 1, height: 30)
    }

    private func fact(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.oneDaySky)
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OneDay.ink)
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }

    /// The day again, scrollable. Same rail, same stamps as the room timeline
    /// — a finished film should still read as the day it came from.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: Strings.wholeDayHeader)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    TimelineRow(
                        stamp: TimelineStamp(
                            label: schedule.railLabel(
                                forSlot: clip.day, recordedAt: clip.recordedAt),
                            caption: schedule.railCaption(
                                forSlot: clip.day, recordedAt: clip.recordedAt),
                            icon: challenge.isOneDay
                                ? schedule.dayPartIcon(recordedAt: clip.recordedAt)
                                : nil,
                            isEmphasized: true),
                        isFirst: index == 0,
                        isLast: index == clips.count - 1,
                        isFilled: true
                    ) {
                        TimelineClip(
                            momentTitle: clip.label ?? presenter.title(forSlot: clip.day),
                            momentIcon: MomentCatalog.icon(
                                for: challenge.momentValue(forSlot: clip.day)),
                            state: .filmed(url: clip.url, recordedAt: clip.recordedAt),
                            authorName: clip.authorName,
                            durationLabel: challenge.resolvedClipLength.secondsLabel,
                            reactions: clip.emoji,
                            mediaHeight: challenge.resolvedOrientation == .landscape ? 130 : 180,
                            showsMomentTitle: !challenge.isTimeOnly)
                    }
                }
            }
        }
    }
}

// MARK: - Actions

private struct FilmActionLabel: View {
    let icon: String
    let label: String
    let accent: Color
    var isBusy = false

    var body: some View {
        VStack(spacing: 7) {
            Group {
                if isBusy {
                    ProgressView().controlSize(.small).tint(accent)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .frame(height: 20)

            Text(label)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .glassSurface(radius: OneDay.Radius.card, tint: accent)
    }
}

private struct FilmAction: View {
    let icon: String
    let label: String
    let accent: Color
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FilmActionLabel(icon: icon, label: label, accent: accent, isBusy: isBusy)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}
