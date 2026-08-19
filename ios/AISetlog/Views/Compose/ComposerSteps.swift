import SwiftUI

/// The two pages of `StoryComposerView`. Stateless — the composer owns every
/// choice; these just render it.

// MARK: - Step 1: pick a mood

/// Nothing on this page but posters. The format and clip-length controls sit
/// under the rack because they change what the posters *say* (moment count,
/// duration chips), so they belong next to them rather than on the next page.
struct MoodStep: View {
    let templates: [ChallengeTemplate]
    @Binding var activeIndex: Int
    @Binding var mode: Challenge.Mode
    @Binding var clipLength: Challenge.ClipLength
    let onBuildOwn: () -> Void
    let onEdit: (ChallengeTemplate) -> Void
    let onDelete: (ChallengeTemplate) -> Void

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var momentCount: Int {
        templates.indices.contains(activeIndex)
            ? (templates[activeIndex].momentKeys?.count ?? 7)
            : 7
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text(Strings.headerTitle(oneDay: mode == .oneDay))
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                        .multilineTextAlignment(.center)

                    Text(Strings.composerSubtitle(
                        count: momentCount,
                        secondsLabel: clipLength.secondsLabel))
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                }
                .padding(.horizontal, 24)

                TemplateCarousel(
                    templates: templates,
                    secondsLabel: clipLength.secondsLabel,
                    isOneDay: mode == .oneDay,
                    activeIndex: $activeIndex,
                    onEdit: onEdit,
                    onDelete: onDelete)

                CarouselDots(count: templates.count, index: activeIndex)

                VStack(spacing: 12) {
                    PillSelector(
                        options: [
                            .init(value: Challenge.Mode.oneDay, label: Strings.modeOneDay),
                            .init(value: Challenge.Mode.sevenDay, label: Strings.modeSevenDay),
                        ],
                        selection: $mode)

                    PillSelector(
                        options: Challenge.ClipLength.allCases.map {
                            .init(value: $0, label: $0.secondsLabel)
                        },
                        selection: $clipLength,
                        compact: true)

                    Button(action: onBuildOwn) {
                        Label(Strings.writeYourOwnMoments, systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.softAction)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Step 2: set it up

/// Solo or together, then the two things that actually change the film: how
/// long each clip runs and which way the frame sits.
struct SetupStep: View {
    let template: ChallengeTemplate?
    @Binding var title: String
    @Binding var titleEdited: Bool
    @Binding var withFriends: Bool
    @Binding var clipLength: Challenge.ClipLength
    @Binding var orientation: Challenge.Orientation
    /// The story's moments, as raw display strings once touched. Editable here
    /// so you can see exactly what you'll be asked to film before committing —
    /// picking a mood shouldn't mean accepting seven prompts sight unseen.
    @Binding var moments: [String]
    let isOneDay: Bool
    let memberNames: [String]
    let errorText: String?

    @FocusState private var titleFocused: Bool
    @State private var momentsExpanded = false
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heading
                nameField
                momentsCard
                companyPicker
                if withFriends { roomExplainer }
                setupCard

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .animation(OneDay.Motion.soft, value: withFriends)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(withFriends ? Strings.withFriends : Strings.composerSetupStep)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
            Text(withFriends ? Strings.createRoomSubtitle : Strings.soloSetupSubtitle)
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
        }
        .padding(.top, 4)
    }

    /// The chosen script, restated small, with the story's editable name.
    private var nameField: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 13) {
                if let template {
                    Image(systemName: template.displaySymbol)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background {
                            TemplateCover(identityKey: template.identityKey)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.storyNameLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)

                    TextField("", text: $title, prompt: Text(Strings.titlePrompt(oneDay: isOneDay)))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                        .tint(Color.oneDayBlue)
                        .focused($titleFocused)
                        .onChange(of: title) { _, _ in
                            if titleFocused { titleEdited = true }
                        }
                }
            }
        }
    }

    /// The moments, spelled out and editable. Collapsed to a summary until you
    /// ask for it, so the page still reads as "set it up" rather than a form.
    private var momentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: Strings.theMoments)
                Spacer()
                Button {
                    withAnimation(OneDay.Motion.soft) { momentsExpanded.toggle() }
                } label: {
                    Label(
                        momentsExpanded ? Strings.hideMoments : Strings.reviewMoments,
                        systemImage: momentsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayBlue)
                }
                .buttonStyle(.plain)
            }

            GlassCard(padding: 14) {
                if momentsExpanded {
                    VStack(spacing: 0) {
                        ForEach(moments.indices, id: \.self) { index in
                            momentRow(index)
                            if index < moments.count - 1 {
                                Divider().overlay(OneDay.hairline).padding(.leading, 38)
                            }
                        }

                        if moments.count < 12 {
                            Divider().overlay(OneDay.hairline).padding(.leading, 38)
                            Button {
                                withAnimation(OneDay.Motion.soft) { moments.append("") }
                            } label: {
                                Label(Strings.addMoment, systemImage: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.oneDayBlue)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    // Collapsed: the whole day as a run of small labels.
                    WrappingMoments(titles: moments.map { MomentCatalog.localize($0) })
                }
            }
        }
    }

    private func momentRow(_ index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: MomentCatalog.icon(for: moments[index]))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.oneDaySky)
                .frame(width: 28, height: 28)
                .background(OneDay.surfaceSoft, in: Circle())

            TextField(
                Strings.promptN(index + 1),
                text: Binding(
                    get: { MomentCatalog.localize(moments[index]) },
                    set: { moments[index] = $0 }))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .tint(Color.oneDayBlue)

            if moments.count > 2 {
                Button {
                    withAnimation(OneDay.Motion.soft) { _ = moments.remove(at: index) }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(OneDay.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 7)
    }

    /// Two big choices, side by side. Cards rather than a toggle — who you're
    /// filming with is the most consequential setting on the page.
    private var companyPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: Strings.whoIsFilming)

            HStack(spacing: 12) {
                CompanyOption(
                    icon: "person.fill",
                    title: Strings.createByYourself,
                    caption: Strings.createByYourselfCaption,
                    accent: .oneDayBlue,
                    isOn: !withFriends
                ) { withFriends = false }

                CompanyOption(
                    icon: "person.2.fill",
                    title: Strings.withFriends,
                    caption: Strings.createWithFriendsCaption,
                    accent: .oneDayLavender,
                    isOn: withFriends
                ) { withFriends = true }
            }

            if withFriends, !memberNames.isEmpty {
                HStack(spacing: 8) {
                    AvatarStack(names: memberNames, maxShown: 5, size: 28)
                    Text(Strings.membersInRoom(memberNames.count))
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                }
                .padding(.top, 2)
            }
        }
    }

    private var roomExplainer: some View {
        HStack(alignment: .top, spacing: 11) {
            OneDayBuddy(size: 34)
            Text(Strings.roomExplainer)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassSurface(radius: OneDay.Radius.card, tint: .oneDayLavender)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var setupCard: some View {
        GlassCard(padding: 16) {
            VStack(spacing: 16) {
                OptionRow(icon: "timer", title: Strings.clipLengthRow) {
                    PillSelector(
                        options: Challenge.ClipLength.allCases.map {
                            .init(value: $0, label: $0.secondsLabel)
                        },
                        selection: $clipLength,
                        compact: true)
                        .frame(width: 150)
                }

                Divider().overlay(OneDay.hairline)

                OptionRow(
                    icon: orientation == .portrait ? "rectangle.portrait" : "rectangle",
                    title: Strings.orientationRow,
                    accent: .oneDayMint
                ) {
                    PillSelector(
                        options: [
                            .init(value: Challenge.Orientation.portrait, label: Strings.orientationPortrait),
                            .init(value: Challenge.Orientation.landscape, label: Strings.orientationLandscape),
                        ],
                        selection: $orientation,
                        compact: true)
                        .frame(width: 172)
                }
            }
        }
    }
}

/// The collapsed moment summary: every title as a small chip, wrapping like
/// text. Shows the shape of the day in one glance without becoming a list.
private struct WrappingMoments: View {
    let titles: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(titles.enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5.5)
                    .background(OneDay.surfaceSoft.opacity(0.85), in: Capsule())
            }
        }
    }
}

/// One of the two "who's filming" cards.
private struct CompanyOption: View {
    let icon: String
    let title: String
    let caption: String
    let accent: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? .white : accent)
                    .frame(width: 38, height: 38)
                    .background(
                        isOn ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.opacity(0.13)),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                Text(title)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(caption)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous)
                    .fill(OneDay.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous)
                            .fill(accent.opacity(isOn ? 0.09 : 0))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: OneDay.Radius.card, style: .continuous)
                    .strokeBorder(
                        isOn ? accent.opacity(0.55) : OneDay.hairline,
                        lineWidth: isOn ? 1.8 : 1)
            }
            .oneDaySoftShadow(strength: isOn ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .animation(OneDay.Motion.snap, value: isOn)
    }
}
