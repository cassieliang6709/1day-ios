import SwiftUI

/// The two pages of `StoryComposerView`. Stateless — the composer owns every
/// choice; these just render it.

// MARK: - Step 1: choose how to record

/// Time-only recording is a first-class mode, not one poster hidden inside a
/// long carousel. Prompted stories sit beside it as the more directed option,
/// with a short recommendation grid and an explicit route to the full library.
struct MoodStep: View {
    let oneDayTemplates: [ChallengeTemplate]
    let sevenDayTemplates: [ChallengeTemplate]
    @Binding var selection: ComposerSelection
    let onBuildOwn: () -> Void
    let onEdit: (ChallengeTemplate) -> Void
    let onDelete: (ChallengeTemplate) -> Void

    @State private var showLibrary = false
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var mode: Challenge.Mode { selection.mode }

    private var currentModeTemplates: [ChallengeTemplate] {
        mode == .oneDay ? oneDayTemplates : sevenDayTemplates
    }

    private var selectedTemplate: ChallengeTemplate? {
        guard let templateID = selection.templateID else { return nil }
        return (oneDayTemplates + sevenDayTemplates).first { $0.id == templateID }
    }

    private var promptTemplates: [ChallengeTemplate] {
        currentModeTemplates.filter { !$0.isTimeOnly }
    }

    private var recommendedTemplates: [ChallengeTemplate] {
        Array(promptTemplates.prefix(4))
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                page(scroll)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showLibrary) {
            TemplateLibraryView(
                oneDayTemplates: oneDayTemplates.filter { !$0.isTimeOnly },
                sevenDayTemplates: sevenDayTemplates,
                selection: $selection,
                onEdit: onEdit,
                onDelete: onDelete)
                .presentationDetents([.large])
        }
    }

    private func page(_ scroll: ScrollViewProxy) -> some View {
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

                // Prompted first: it's the default, and it's the one whose
                // consequences (the grid below) are visible on this screen.
                HStack(alignment: .top, spacing: 12) {
                    RecordingModeCard(
                        title: Strings.promptChallengeTitle,
                        caption: Strings.promptChallengeCaption,
                        imageName: "TemplateLockIn",
                        symbol: "scope",
                        isSelected: selection.style == .prompted,
                        action: selectPromptMode)

                    RecordingModeCard(
                        title: Strings.timeRecordingTitle,
                        caption: Strings.timeRecordingCaption,
                        imageName: "TemplatePerfectDay",
                        symbol: "point.3.connected.trianglepath.dotted",
                        isSelected: selection.style == .timeOnly,
                        action: selectTimeOnly)
                }
                .padding(.horizontal, 20)

                PromptPreviewStrip(
                    template: selection.style == .timeOnly ? nil : selectedTemplate,
                    onSwap: {
                        withAnimation(OneDay.Motion.soft) {
                            scroll.scrollTo(Self.recommendationsAnchor, anchor: .top)
                        }
                    })
                    .padding(.horizontal, 20)

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

                promptSection
                    .id(Self.recommendationsAnchor)
            }
            .padding(.bottom, 16)
    }

    /// Scroll target for the preview strip's "swap" link.
    private static let recommendationsAnchor = "recommendations"

    /// The recommendations. Dimmed and inert while "record by time" is chosen —
    /// they used to stay live, so one tap would quietly take you out of the mode
    /// you'd just picked without the cards above ever saying so.
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionLabel(text: mode == .oneDay
                    ? Strings.recommendedPrompts
                    : Strings.sevenDayChallenges)
                Spacer()
                if selection.promptGridEnabled {
                    Button {
                        showLibrary = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(Strings.moreTemplates)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayBlue)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(Strings.promptsNotNeeded)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)
                }
            }
            .padding(.horizontal, 20)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(recommendedTemplates) { template in
                    PromptTemplateTile(
                        template: template,
                        isSelected: selection.templateID == template.id,
                        onSelect: { select(template) },
                        onEdit: template.isCustom ? { onEdit(template) } : nil,
                        onDelete: template.isCustom ? { onDelete(template) } : nil)
                }
            }
            .padding(.horizontal, 20)
        }
        .disabled(!selection.promptGridEnabled)
        .opacity(selection.promptGridEnabled ? 1 : 0.4)
        .animation(OneDay.Motion.soft, value: selection.promptGridEnabled)
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

/// The prompts you're actually signing up for, spelled out before you commit.
///
/// Until now this screen showed a template's name and a mood line, and the
/// seven questions only appeared on the *next* step behind a collapsed card —
/// so "pick a story" meant accepting seven prompts sight unseen.
private struct PromptPreviewStrip: View {
    /// Nil when the story has no prompts to preview: time-only, or the guided
    /// flow's own moments, which aren't a template.
    let template: ChallengeTemplate?
    let onSwap: () -> Void

    private var moments: [String] {
        template?.momentKeys?.map { MomentCatalog.localize($0) } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let template, !moments.isEmpty {
                HStack(spacing: 6) {
                    Text(template.displayName)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.inkFaint)

                    Text(Strings.promptCountLabel(moments.count))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .lineLimit(1)
                        .fixedSize()

                    Spacer(minLength: 6)

                    Button(action: onSwap) {
                        HStack(spacing: 3) {
                            Text(Strings.swapTemplate)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayBlue)
                    }
                    .buttonStyle(.plain)
                }

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
            } else {
                Label(Strings.timeOnlyPreviewBody, systemImage: "clock.badge.checkmark")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .glassSurface(radius: OneDay.Radius.card, tint: .oneDayBlue)
        .animation(OneDay.Motion.soft, value: template?.id)
    }
}

private struct RecordingModeCard: View {
    let title: String
    let caption: String
    let imageName: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 76)
                        .clipped()

                    LinearGradient(
                        colors: [.clear, .white.opacity(0.94)],
                        startPoint: .top,
                        endPoint: .bottom)

                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.oneDayBlue)
                        .frame(width: 34, height: 34)
                        .background(.white, in: RoundedRectangle(cornerRadius: 11))
                        .shadow(color: OneDay.ink.opacity(0.1), radius: 7, y: 3)
                        .padding(10)
                }
                .frame(height: 76)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                    Text(caption)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .lineLimit(2)
                        .frame(minHeight: 32, alignment: .topLeading)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(OneDay.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        isSelected ? Color.oneDayBlue.opacity(0.62) : OneDay.hairline,
                        lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(OneDay.brandHorizontal, in: Circle())
                        .padding(9)
                }
            }
            .oneDaySoftShadow(strength: isSelected ? 0.85 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

private struct TemplateLibraryView: View {
    let oneDayTemplates: [ChallengeTemplate]
    let sevenDayTemplates: [ChallengeTemplate]
    @Binding var selection: ComposerSelection
    let onEdit: (ChallengeTemplate) -> Void
    let onDelete: (ChallengeTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var templates: [ChallengeTemplate] {
        selection.mode == .oneDay ? oneDayTemplates : sevenDayTemplates
    }

    private var mode: Binding<Challenge.Mode> {
        Binding(get: { selection.mode }, set: { selection.setMode($0) })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 2)

                ScrollView {
                    VStack(spacing: 16) {
                        PillSelector(
                            options: [
                                .init(value: Challenge.Mode.oneDay, label: Strings.modeOneDay),
                                .init(value: Challenge.Mode.sevenDay, label: Strings.modeSevenDay),
                            ],
                            selection: mode)

                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(templates) { template in
                                PromptTemplateTile(
                                    template: template,
                                    isSelected: selection.templateID == template.id,
                                    onSelect: { select(template) },
                                    subtitle: .blurb,
                                    onEdit: template.isCustom ? { onEdit(template) } : nil,
                                    onDelete: template.isCustom ? { onDelete(template) } : nil)
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(Strings.moreTemplates)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) { dismiss() }
                }
            }
        }
    }

    private func select(_ template: ChallengeTemplate) {
        selection.select(template, oneDay: oneDayTemplates, sevenDay: sevenDayTemplates)
        dismiss()
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
    let errorText: String?

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
