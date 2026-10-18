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
    /// This exact render is already in Photos. The button says so and stops
    /// taking taps until a new render replaces the file.
    var isSaved = false
    let saveMessage: String?
    /// Set when the message is a permission refusal, so the line can carry the
    /// way out of it. Nil for "saved" and for an ordinary failure, neither of
    /// which iOS Settings can do anything about.
    var onOpenSettings: (() -> Void)?
    /// Saves the film as it sounds now: with its music and voiceover, if any.
    let onSave: (URL) -> Void
    let onAdjust: () -> Void

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @Environment(\.roomPreviewMediaScope) private var previewMedia
    @Environment(MoodStore.self) private var moodStore: MoodStore?
    /// `filmURL` remixed by `FilmSoundtrackPanel`; nil while it's the original.
    @State private var mixedURL: URL?

    private var shownURL: URL { mixedURL ?? filmURL }

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
                FilmSoundtrackPanel(
                    baseURL: filmURL,
                    mood: moodStore?.mood(on: challenge.startDate)?.mood,
                    mixedURL: $mixedURL)
                actions
                facts
                timeline
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, OneDay.tabBarClearance + 24)
        }
        .scrollIndicators(.hidden)
        // Over the page, above the tab bar, rather than hung under the
        // buttons with an offset — that version overlapped the facts strip
        // and needed a padding hack on it to make room.
        .overlay(alignment: .bottom) {
            if let saveMessage, onOpenSettings == nil {
                toast(saveMessage)
                    .padding(.bottom, OneDay.tabBarClearance + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(OneDay.Motion.soft, value: saveMessage)
    }

    /// Just the title. The line under it — 「属于你这一天的小影片。」 — said
    /// nothing the player below doesn't, and the facts strip already gives the
    /// real numbers.
    private var heading: some View {
        Text(Strings.filmReadyTitle)
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .foregroundStyle(OneDay.ink)
            .multilineTextAlignment(.center)
    }

    private func toast(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13.5, weight: .bold, design: .rounded))
            .foregroundStyle(OneDay.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(OneDay.hairline, lineWidth: 1))
            .oneDaySoftShadow()
            .padding(.horizontal, 20)
            .accessibilityAddTraits(.isStaticText)
    }

    private var player: some View {
        VlogPlayer(
            url: shownURL,
            aspectRatio: challenge.resolvedOrientation == .landscape ? 16 / 9 : 9 / 16)
            // The player reads its URL once; a remix is a new player.
            .id(shownURL)
            .frame(maxHeight: 460)
    }

    /// Save, share, adjust — three equal-weight actions, because at this point
    /// there's no single "correct" next step.
    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 11) {
                FilmAction(
                    icon: isSaved
                        ? "checkmark.circle.fill"
                        : (isSaving ? "arrow.down.circle" : "square.and.arrow.down"),
                    label: isSaved
                        ? Strings.savedLabel
                        : (isSaving ? Strings.saving : Strings.saveAction),
                    accent: .oneDayBrand,
                    isBusy: isSaving,
                    action: { onSave(shownURL) })
                    .disabled(previewMedia != nil || isSaved)

                ShareLink(item: shownURL) {
                    FilmActionLabel(
                        icon: "paperplane.fill",
                        label: Strings.shareAction,
                        accent: .oneDayLavender)
                }
                .buttonStyle(.plain)
                .disabled(previewMedia != nil)

                FilmAction(
                    icon: "slider.horizontal.3",
                    label: Strings.adjust,
                    accent: .oneDayMint,
                    action: onAdjust)
            }

            // Two greyed-out buttons with no reason given read as broken.
            if previewMedia != nil {
                Text(Strings.sampleCantSaveOrShare)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                    .multilineTextAlignment(.center)
            }

            // A refusal is not a toast: it stays, in the flow of the page,
            // because it carries the way out. "需要相册权限才能保存视频。"
            // used to be the whole of it — a sentence about a switch in
            // another app, with no way to reach the switch.
            if let saveMessage, let onOpenSettings {
                VStack(spacing: 4) {
                    Text(saveMessage)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .multilineTextAlignment(.center)
                    Button(Strings.openSystemSettings, action: onOpenSettings)
                        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.brandText)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("film-open-settings")
                }
                .transition(.opacity)
            }
        }
    }

    /// Duration, moment count, people — the film's stats in one strip.
    private var facts: some View {
        HStack(spacing: 0) {
            fact(icon: "clock", title: Strings.durationLabel, value: schedule.filmDuration())
            divider
            fact(
                icon: "circle.grid.2x2.fill",
                title: Strings.momentsLabel,
                // Moments, not clips — three people on one moment is one.
                value: "\(Set(clips.map(\.day)).count)")
            divider
            fact(
                icon: "person.2.fill",
                title: Strings.peopleLabel,
                value: "\(max(contributors.count, 1))")
        }
        .padding(.vertical, 14)
        .glassSurface(radius: OneDay.Radius.card)
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
                            // `clip.label` is 「第 N 天」 for a room slot
                            // with no name (it is built for the solo story's
                            // wording); a room says the name or nothing.
                            momentTitle: challenge.isShared
                                ? (presenter.momentName(forSlot: clip.day) ?? "")
                                : (clip.label ?? presenter.title(forSlot: clip.day)),
                            momentIcon: MomentCatalog.icon(
                                for: challenge.momentValue(forSlot: clip.day)),
                            state: .filmed(url: clip.url, recordedAt: clip.recordedAt),
                            authorName: clip.authorName,
                            durationLabel: challenge.resolvedClipLength.secondsLabel,
                            reactions: clip.emoji,
                            mediaHeight: challenge.resolvedOrientation == .landscape ? 130 : 180,
                            showsMomentTitle: !challenge.isTimeOnly
                                && (!challenge.isShared
                                    || presenter.momentName(forSlot: clip.day) != nil))
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
