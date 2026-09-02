import SwiftUI

/// The two pages of `StoryComposerView`. Stateless — the composer owns every
/// choice; these just render it.

// MARK: - Step 1: choose how to record

/// One choice, not two. This screen used to ask twice: two 150pt posters for
/// "prompt challenge vs record by time", and then a grid of templates below —
/// where picking a poster could silently flip the mode above it. The prompts
/// themselves appeared a third time, in a preview strip in between.
///
/// Now the pill at the top only *filters*: it says which kind of story this is,
/// and the one thing below it answers accordingly. The prompts live on the card
/// you selected, and nowhere else.
struct MoodStep: View {
    let oneDayTemplates: [ChallengeTemplate]
    let sevenDayTemplates: [ChallengeTemplate]
    @Binding var selection: ComposerSelection
    let onBuildOwn: () -> Void
    let onEdit: (ChallengeTemplate) -> Void
    let onDelete: (ChallengeTemplate) -> Void

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var mode: Challenge.Mode { selection.mode }

    private var currentModeTemplates: [ChallengeTemplate] {
        mode == .oneDay ? oneDayTemplates : sevenDayTemplates
    }

    private var promptTemplates: [ChallengeTemplate] {
        currentModeTemplates.filter { !$0.isTimeOnly }
    }

    /// The one-day / seven-day switch, which used to live inside the "more
    /// templates" sheet — the only place it existed. When that sheet wouldn't
    /// open, seven-day challenges were unreachable from the whole app.
    private var modeSelection: Binding<Challenge.Mode> {
        Binding(get: { selection.mode }, set: { selection.setMode($0) })
    }

    private var timeOnlyTemplate: ChallengeTemplate? {
        oneDayTemplates.first(where: \.isTimeOnly)
    }

    /// The pill writes through to the selection so the two can't disagree —
    /// that disagreement is the bug this screen was rebuilt around.
    private var style: Binding<ComposerSelection.Style> {
        Binding(
            get: { selection.style },
            set: { next in
                switch next {
                case .timeOnly: selectTimeOnly()
                case .prompted: selectPromptMode()
                }
            })
    }

    var body: some View {
        ScrollView {
            page
        }
        .scrollIndicators(.hidden)
    }

    private var page: some View {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(Strings.newStoryQuestion)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.ink)

                    Text(Strings.recordingStyleSubtitle)
                        .font(.system(size: 14.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                }
                .padding(.horizontal, 20)

                PillSelector(
                    options: [
                        .init(value: ComposerSelection.Style.prompted, label: Strings.followPrompts),
                        .init(value: ComposerSelection.Style.timeOnly, label: Strings.recordByTime),
                    ],
                    selection: style)
                    .padding(.horizontal, 20)

                if selection.promptGridEnabled {
                    promptSection
                } else {
                    timeOnlySection
                }

                Button(action: onBuildOwn) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.oneDayLavender)
                            .frame(width: 42, height: 42)
                            .background(Color.oneDayLavender.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(Strings.customPromptsTitle)
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                                .foregroundStyle(OneDay.ink)
                            Text(Strings.customPromptsCaption)
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(OneDay.inkSoft)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(OneDay.inkFaint)
                    }
                    .padding(13)
                    .background(OneDay.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(OneDay.hairline, lineWidth: 1))
                    .oneDaySoftShadow(strength: 0.45)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.customPromptsTitle)
                .accessibilityIdentifier("custom-prompts-entry")
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
    }

    /// The chosen story, opened up, then the alternatives. The selected card
    /// rises to the top rather than expanding where it sits: full width is the
    /// only way seven prompts fit, and a card that grows sideways out of one
    /// grid column has to shove its neighbour somewhere.
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: mode == .oneDay
                    ? Strings.pickPromptSet
                    : Strings.sevenDayChallenges)
                Spacer()
            }
            .padding(.horizontal, 20)

            // One day or seven. This is the question the grid below is an
            // answer to, so it sits above the grid rather than behind a sheet.
            PillSelector(
                options: [
                    .init(value: Challenge.Mode.oneDay, label: Strings.modeOneDay),
                    .init(value: Challenge.Mode.sevenDay, label: Strings.modeSevenDay),
                ],
                selection: modeSelection)
                .padding(.horizontal, 20)

            if let chosen = selectedPromptTemplate {
                OpenTemplateCard(template: chosen) {
                    MomentChips(moments: chosen.momentKeys?
                        .map { MomentCatalog.localize($0) } ?? [])
                }
                .padding(.horizontal, 20)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(alternativeTemplates) { template in
                    PromptTemplateTile(
                        template: template,
                        isSelected: false,
                        onSelect: { select(template) },
                        onEdit: template.isCustom ? { onEdit(template) } : nil,
                        onDelete: template.isCustom ? { onDelete(template) } : nil)
                }
            }
            .padding(.horizontal, 20)
        }
        .animation(OneDay.Motion.soft, value: selection.templateID)
    }

    /// Record-by-time replaces the grid instead of dimming it. The old screen
    /// left five posters sitting there greyed out — an answer to a question
    /// nobody asked, and still the most eye-catching thing on screen.
    private var timeOnlySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let template = timeOnlyTemplate {
                SectionLabel(text: template.displayName)
                    .padding(.horizontal, 20)

                OpenTemplateCard(template: template, showsPromptCount: false) {
                    Text(Strings.timeOnlyCardBody)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)

                Label(Strings.timeOnlyCaptionNote, systemImage: "clock")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
        }
    }

    /// The prompted story currently chosen. Nil during the guided flow, whose
    /// moments aren't backed by a template.
    private var selectedPromptTemplate: ChallengeTemplate? {
        guard let templateID = selection.templateID else { return nil }
        return promptTemplates.first { $0.id == templateID }
    }

    /// Everything except the one already open above.
    ///
    /// All of them, not the first five. The cut-off was there to justify a
    /// "more templates" sheet, and its side effect was that a template you
    /// wrote yourself — always last in the list — could never appear on this
    /// screen at all.
    private var alternativeTemplates: [ChallengeTemplate] {
        promptTemplates.filter { $0.id != selectedPromptTemplate?.id }
    }

    private func selectTimeOnly() {
        selection.selectTimeOnly(in: oneDayTemplates)
    }

    private func selectPromptMode() {
        selection.selectPrompted(in: currentModeTemplates)
    }

    private func select(_ template: ChallengeTemplate) {
        selection.select(template, oneDay: oneDayTemplates, sevenDay: sevenDayTemplates)
    }
}

/// The story you've chosen, opened up: cover, name, and — right there on the
/// card — exactly what it will ask you to film.
///
/// The prompts used to be spread across three places on this screen (a preview
/// strip, a tile subtitle, and the next step behind a collapsed card). They
/// live here now, and only here.
private struct OpenTemplateCard<Detail: View>: View {
    let template: ChallengeTemplate
    /// Off for the time-only story, which has no prompts to count.
    var showsPromptCount = true
    @ViewBuilder var detail: Detail

    private var promptCount: Int { template.momentKeys?.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(template.coverAssetName ?? "TemplateCustomStory")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 118)
                .clipped()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(template.displayName)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                        .lineLimit(1)

                    if showsPromptCount, promptCount > 0 {
                        Text("·")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(OneDay.inkFaint)
                        Text(Strings.promptCountLabel(promptCount))
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                            .fixedSize()
                    }

                    Spacer(minLength: 4)
                }

                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
        }
        .background(OneDay.surface, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.oneDayBlue.opacity(0.65), lineWidth: 2)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.oneDayBlue)
                .padding(9)
        }
        .oneDaySoftShadow(strength: 0.8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isSelected)
    }
}

/// The prompts, numbered, in the order they'll be asked for.
private struct MomentChips: View {
    let moments: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(moments.enumerated()), id: \.offset) { index, moment in
                HStack(spacing: 4) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Color.oneDayBlue)
                    Text(moment)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
                .background(OneDay.surfaceSoft.opacity(0.9), in: Capsule())
            }
        }
    }
}

private struct PromptTemplateTile: View {
    /// What the second line says. The recommendation grid is the last place
    /// before committing, so there it names actual prompts; the library is for
    /// browsing by feel, so there the mood line still earns its place.
    enum Subtitle { case prompts, blurb }

    let template: ChallengeTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    var subtitle: Subtitle = .prompts
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    /// "起床 · 咖啡 · 收拾出门…" — enough to recognise the day's shape in a
    /// tile this size. Falls back to the blurb for templates without prompts.
    private var subtitleText: String {
        guard subtitle == .prompts, let keys = template.momentKeys, !keys.isEmpty else {
            return template.displayBlurb
        }
        let head = keys.prefix(3).map { MomentCatalog.localize($0) }.joined(separator: " · ")
        return keys.count > 3 ? head + "…" : head
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                Image(template.coverAssetName ?? "TemplateCustomStory")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipped()

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.displayName)
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .lineLimit(2)
                        .frame(minHeight: 30, alignment: .topLeading)
                }
                .padding(11)
            }
            .background(OneDay.surface, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isSelected ? Color.oneDayBlue.opacity(0.65) : OneDay.hairline,
                        lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.oneDayBlue)
                        .padding(8)
                }
            }
            .oneDaySoftShadow(strength: isSelected ? 0.75 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            if let onEdit {
                Button(Strings.editTemplate, systemImage: "pencil", action: onEdit)
            }
            if let onDelete {
                Button(Strings.deleteTemplate, systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
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
    let isTimeOnly: Bool
    let memberNames: [String]

    @FocusState private var titleFocused: Bool
    @State private var momentsExpanded = false
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heading
                if isTimeOnly {
                    timeOnlyCard
                } else {
                    nameField
                    momentsCard
                }
                companyPicker
                if withFriends { roomExplainer }
                setupCard
                // Failures live in the footer next to the button that caused
                // them — at the end of this scroll they were below the fold,
                // so "Create room" looked like it did nothing at all.
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .animation(OneDay.Motion.soft, value: withFriends)
    }

    private var timeOnlyCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.oneDayBlue)
                .frame(width: 42, height: 42)
                .background(Color.oneDayBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.timeOnlySetupTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Text(Strings.timeOnlySetupBody)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .glassSurface(radius: OneDay.Radius.card, tint: .oneDayBlue)
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
                    Image(template.coverAssetName ?? "TemplateCustomStory")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .accessibilityHidden(true)
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

    /// - Note: every read of `moments[index]` is bounds-checked. `ForEach` over
    ///   `indices` with `id: \.self` will evaluate a row body for an index the
    ///   array no longer has, in the same frame the removal below animates —
    ///   a raw subscript there traps. Deleting a prompt used to crash the app.
    private func momentRow(_ index: Int) -> some View {
        let moment = moments.indices.contains(index) ? moments[index] : ""

        return HStack(spacing: 10) {
            Image(systemName: MomentCatalog.icon(for: moment))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.oneDaySky)
                .frame(width: 28, height: 28)
                .background(OneDay.surfaceSoft, in: Circle())

            TextField(
                Strings.promptN(index + 1),
                text: Binding(
                    get: { MomentCatalog.localize(moment) },
                    set: { if moments.indices.contains(index) { moments[index] = $0 } }))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .tint(Color.oneDayBlue)

            if moments.count > 2 {
                Button {
                    withAnimation(OneDay.Motion.soft) {
                        guard moments.indices.contains(index) else { return }
                        moments.remove(at: index)
                    }
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
