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
    @State private var showsAdjust = false

    private var shownURL: URL { mixedURL ?? filmURL }

    private var schedule: StorySchedule { StorySchedule(challenge) }
    private var presenter: ChallengePresenter { ChallengePresenter(challenge: challenge) }
    private var contributors: [String] {
        Array(Set(clips.compactMap(\.authorName))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OneDay.Space.l) {
                heading
                player
                adjustToggle
                if showsAdjust {
                    if let onFilter, !people.isEmpty {
                        FilmPeopleRow(people: people, selection: selection, onOpen: onFilter)
                    }
                    FilmSoundtrackPanel(
                        baseURL: filmURL,
                        mood: moodStore?.mood(on: challenge.startDate)?.mood,
                        mixedURL: $mixedURL)
                    lookRow
                }
                timeline
                    .padding(.top, OneDay.Space.s)
            }
            .padding(.horizontal, OneDay.Space.xl)
            .padding(.top, OneDay.Space.xxl)
            .padding(.bottom, OneDay.Space.xxl)
        }
        .scrollIndicators(.hidden)
        // Save / Share stay reachable without scrolling; the floating tab bar is always on screen, so sit above it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
                .padding(.horizontal, OneDay.Space.xl)
                .padding(.top, OneDay.Space.s)
                .padding(.bottom, OneDay.tabBarClearance)
        }
        .overlay(alignment: .bottom) {
            if let saveMessage, onOpenSettings == nil {
                toast(saveMessage)
                    .padding(.bottom, OneDay.tabBarClearance + 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(OneDay.Motion.soft, value: saveMessage)
        .animation(OneDay.Motion.soft, value: showsAdjust)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: OneDay.Space.xs) {
            Text(Strings.filmReadyTitle)
                .font(OneDay.Font.caption)
                .foregroundStyle(OneDay.brandText)
            Text(challenge.title)
                .font(OneDay.Font.title)
                .foregroundStyle(OneDay.ink)
                .lineLimit(2)
            Text(Strings.filmMeta(
                duration: schedule.filmDuration(),
                clips: clips.count,
                people: max(contributors.count, 1)))
                .font(OneDay.Font.subhead)
                .foregroundStyle(OneDay.inkSoft)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("film-heading")
    }

    private var adjustToggle: some View {
        Button {
            showsAdjust.toggle()
        } label: {
            HStack(spacing: OneDay.Space.m) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(OneDay.brandText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.filmAdjustTitle)
                        .font(OneDay.Font.callout)
                        .foregroundStyle(OneDay.ink)
                    Text(Strings.filmAdjustSummary)
                        .font(OneDay.Font.caption)
                        .foregroundStyle(OneDay.inkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(OneDay.Font.caption)
                    .foregroundStyle(OneDay.inkFaint)
                    .rotationEffect(.degrees(showsAdjust ? 180 : 0))
            }
            .padding(OneDay.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(radius: OneDay.Radius.card)
            .contentShape(RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(showsAdjust ? .isSelected : [])
        .accessibilityIdentifier("film-adjust-toggle")
    }

    private var lookRow: some View {
        Button(action: onAdjust) {
            HStack(spacing: OneDay.Space.m) {
                Image(systemName: "camera.filters")
                    .foregroundStyle(OneDay.brandText)
                Text(Strings.filmLookRow)
                    .font(OneDay.Font.callout)
                    .foregroundStyle(OneDay.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(OneDay.Font.caption)
                    .foregroundStyle(OneDay.inkFaint)
            }
            .padding(OneDay.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(radius: OneDay.Radius.card)
            .contentShape(RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("film-adjust")
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
            .frame(maxHeight: 520)
            .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: OneDay.Space.s) {
            HStack(spacing: OneDay.Space.m) {
                Button {
                    onSave(shownURL)
                } label: {
                    HStack(spacing: OneDay.Space.s) {
                        if isSaving {
                            ProgressView().controlSize(.small).tint(OneDay.onBrand)
                        } else {
                            Image(systemName: isSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        }
                        Text(isSaved ? Strings.savedLabel : (isSaving ? Strings.saving : Strings.saveAction))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .disabled(previewMedia != nil || isSaved || isSaving)
                .accessibilityIdentifier("film-save")

                ShareLink(item: shownURL) {
                    Label(Strings.shareAction, systemImage: "paperplane.fill")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.softAction)
                .disabled(previewMedia != nil)
                .accessibilityIdentifier("film-share")
            }

            if previewMedia != nil {
                Text(Strings.sampleCantSaveOrShare)
                    .font(OneDay.Font.caption)
                    .foregroundStyle(OneDay.inkFaint)
                    .multilineTextAlignment(.center)
            }

            if let saveMessage, let onOpenSettings {
                VStack(spacing: OneDay.Space.xs) {
                    Text(saveMessage)
                        .font(OneDay.Font.caption)
                        .foregroundStyle(OneDay.inkSoft)
                        .multilineTextAlignment(.center)
                    Button(Strings.openSystemSettings, action: onOpenSettings)
                        .font(OneDay.Font.callout)
                        .foregroundStyle(OneDay.brandText)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("film-open-settings")
                }
                .transition(.opacity)
            }
        }
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


