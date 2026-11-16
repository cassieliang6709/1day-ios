import SwiftUI

struct FinalFilmTimeline: View {
    let challenge: Challenge
    let clips: [DayClip]
    let filmURL: URL
    let isSaving: Bool
    var isSaved = false
    let saveMessage: String?
    var onOpenSettings: (() -> Void)?
    let onSave: (URL) -> Void
    let onAdjust: () -> Void
    var people: [FilmPerson] = []
    var selection = FilmSelection()
    var onFilter: ((FilmFilterTarget) -> Void)?

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    @Environment(\.roomPreviewMediaScope) private var previewMedia
    @Environment(MoodStore.self) private var moodStore: MoodStore?
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
                player
                if let onFilter, !people.isEmpty {
                    FilmPeopleRow(people: people, selection: selection, onOpen: onFilter)
                }
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
        .overlay(alignment: .bottom) {
            if let saveMessage, onOpenSettings == nil {
                toast(saveMessage)
                    .padding(.bottom, OneDay.tabBarClearance + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(OneDay.Motion.soft, value: saveMessage)
    }

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
            .id(shownURL)
            .frame(maxHeight: 460)
    }

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
                    .accessibilityIdentifier("film-save")

                ShareLink(item: shownURL) {
                    FilmActionLabel(
                        icon: "paperplane.fill",
                        label: Strings.shareAction,
                        accent: .oneDayLavender)
                }
                .buttonStyle(.plain)
                .disabled(previewMedia != nil)
                .accessibilityIdentifier("film-share")

                FilmAction(
                    icon: "slider.horizontal.3",
                    label: Strings.adjust,
                    accent: .oneDayMint,
                    action: onAdjust)
                    .accessibilityIdentifier("film-adjust")
            }

            if previewMedia != nil {
                Text(Strings.sampleCantSaveOrShare)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                    .multilineTextAlignment(.center)
            }

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

    private var facts: some View {
        HStack(spacing: 0) {
            fact(icon: "clock", title: Strings.durationLabel, value: schedule.filmDuration())
            divider
            fact(
                icon: "circle.grid.2x2.fill",
                title: Strings.momentsLabel,
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
