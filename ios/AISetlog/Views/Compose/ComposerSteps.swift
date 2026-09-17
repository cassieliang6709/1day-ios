import SwiftUI

/// The two pages of `StoryComposerView`. Stateless — the composer owns every
/// choice; these just render it.

// MARK: - The poster rack

/// Which shelf of posters the grid is showing.
///
/// These four replace two stacked `PillSelector`s (按提示拍/按时间拍, then
/// 一日/七日, with a `SectionLabel` wedged between them) and the 自己写题目 row
/// that used to sit under the grid. All three were answering the same question
/// — what kind of story is today — in three different shapes, and the middle
/// one could silently move the first one's answer.
///
/// The rack only filters. It deliberately does *not* write through to
/// `ComposerSelection`: with a poster tap creating the story outright, the
/// style and mode are read off the poster you tapped, so there is no second
/// copy of that state to keep in step.
enum TemplateRack: Hashable {
    case oneDay
    case sevenDay
    case byTime
    case custom
}

/// The composer's first screen: one question, one row of filters, one rack of
/// posters. Tapping a poster opens its settings, and the settings page is where
/// the story gets made.
///
/// Three shapes, for the record, because the current one looks like the first:
///
/// 1. **1/2 选拍法 → 2/2 设置故事.** A 下一步 button that only ever applied to
///    whichever poster happened to be selected by default, so tapping any other
///    one skipped the second screen entirely.
/// 2. **The poster is the submit button.** Tapping created the story with
///    defaults and left for the camera; the gear on a poster's corner was the
///    only way to the settings. Fast, but 和朋友一起 lived behind a 26pt gear —
///    the most consequential choice in the app, hidden in a corner, while the
///    obvious gesture silently chose 自己来.
/// 3. **Now:** a poster opens the settings page. One page, every decision on
///    it — who you're filming with included — and the button at the bottom both
///    creates the story and starts it.
///
/// So there is no gear any more (the poster *is* the gear) and no "选一张，就
/// 建好了" (it no longer does).
struct MoodStep: View {
    /// Built-ins only. The user's own sets live on the 自己写 rack, so the two
    /// lists are passed apart rather than concatenated.
    let oneDayBuiltins: [ChallengeTemplate]
    let sevenDayTemplates: [ChallengeTemplate]
    let customTemplates: [ChallengeTemplate]
    @Binding var rack: TemplateRack
    let onBuildOwn: () -> Void
    /// A poster tap adopts that script and opens the settings page. It used to
    /// create the story outright; see this type's note.
    let onChoose: (ChallengeTemplate) -> Void
    let onEdit: (ChallengeTemplate) -> Void
    let onDelete: (ChallengeTemplate) -> Void
    /// Where a template's own cover picture lives, asked of the store rather
    /// than looked up here — this layer doesn't know about Documents.
    var coverURL: (ChallengeTemplate) -> URL? = { _ in nil }

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    /// The posters on the current shelf.
    private var shown: [ChallengeTemplate] {
        switch rack {
        case .oneDay: oneDayBuiltins.filter { !$0.isTimeOnly }
        case .sevenDay: sevenDayTemplates
        case .byTime: oneDayBuiltins.filter(\.isTimeOnly)
        case .custom: customTemplates
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(Strings.newStoryQuestion)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .accessibilityIdentifier("composer-question")
                    .padding(.horizontal, 20)

                // Above the racks, not inside one. It isn't a fifth shelf of
                // posters — it's the other way in, for a day no template
                // describes, and it was previously the least visible thing on
                // the screen while being the only one that adapts to today.
                writeYourOwn

                PillSelector(
                    options: [
                        .init(value: TemplateRack.oneDay, label: Strings.modeOneDay),
                        .init(value: TemplateRack.sevenDay, label: Strings.modeSevenDay),
                        .init(value: TemplateRack.byTime, label: Strings.rackByTime),
                        .init(value: TemplateRack.custom, label: Strings.rackCustom),
                    ],
                    selection: $rack,
                    compact: true)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("composer-rack")

                grid
            }
            // Clears the floating capsule. This screen was a `fullScreenCover`
            // until 1.3, with nothing under it to get out of the way of; as the
            // 新建 tab the last row of posters scrolled under 计划/新建/拍摄 and
            // stopped there.
            .padding(.bottom, OneDay.tabBarClearance + 16)
            .animation(OneDay.Motion.soft, value: rack)
        }
        .scrollIndicators(.hidden)
    }

    /// Every poster the same size. The prompts each one will ask for are the
    /// tile's second line, which is the only place they appear on this screen.
    private var grid: some View {
        VStack(alignment: .leading, spacing: 12) {
            if shown.isEmpty {
                Text(Strings.noCustomTemplatesYet)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(shown) { template in
                    PromptTemplateTile(
                        template: template,
                        isSelected: false,
                        coverURL: coverURL(template),
                        onSelect: { onChoose(template) },
                        onEdit: template.isCustom ? { onEdit(template) } : nil,
                        onDelete: template.isCustom ? { onDelete(template) } : nil)
                }
            }
            .padding(.horizontal, 20)

            if rack == .byTime {
                Label(Strings.timeOnlyCaptionNote, systemImage: "clock")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
        }
    }

    /// The way in for a day no poster describes: say what today is for, and
    /// the prompts come back written.
    ///
    /// In the brand gradient rather than white glass, because it has to hold
    /// its own directly above a wall of poster artwork — and because the
    /// screen it opens leads with the same ✨ and the same promise. A rounded
    /// card and not a capsule: this goes somewhere, it doesn't submit.
    private var writeYourOwn: some View {
        Button(action: onBuildOwn) {
            HStack(spacing: 13) {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.22), in: RoundedRectangle(
                        cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.customPromptsTitle)
                        .font(.system(size: 16.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(Strings.customPromptsLead)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(14)
            .background(
                OneDay.brandHorizontal,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .oneDayGlow(.oneDayBrand, strength: 0.7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.customPromptsTitle)
        .accessibilityIdentifier("custom-prompts-entry")
        .padding(.horizontal, 20)
    }
}

private struct PromptTemplateTile: View {
    /// What the second line says. The recommendation grid is the last place
    /// before committing, so there it names actual prompts; the library is for
    /// browsing by feel, so there the mood line still earns its place.
    enum Subtitle { case prompts, blurb }

    let template: ChallengeTemplate
    let isSelected: Bool
    var coverURL: URL?
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
        // The gear is a *sibling* of the poster button, not an overlay inside
        // its label. A Button nested in another Button's label gets flattened:
        // the outer one swallows both the tap and the accessibility element,
        // so the gear rendered but could never be pressed. That went unnoticed
        // while it was only a shortcut past 下一步 — now it is the only way to
        // reach the story's settings at all.
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) { card }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .contextMenu {
                    if let onEdit {
                        Button(Strings.editTemplate, systemImage: "pencil", action: onEdit)
                    }
                    if let onDelete {
                        Button(
                            Strings.deleteTemplate, systemImage: "trash",
                            role: .destructive, action: onDelete)
                    }
                }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            TemplateCoverImage(
                assetName: template.matchedCoverAssetName, fileURL: coverURL)
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(1.6, contentMode: .fit)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

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
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    isSelected ? Color.oneDayBrand.opacity(0.65) : OneDay.hairline,
                    lineWidth: isSelected ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 21, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.oneDayBrand)
                    .padding(8)
            }
        }
        .oneDaySoftShadow(strength: isSelected ? 0.75 : 0.35)
    }
}

// MARK: - Step 2: set it up

/// Solo or together, then the two things that actually change the film: how
/// long each clip runs and which way the frame sits.
struct SetupStep: View {
    let template: ChallengeTemplate?
    /// The template's own cover picture, if the user uploaded one.
    var templateCoverURL: URL?
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

    @FocusState private var titleFocused: Bool
    @State private var momentsExpanded = false

    /// The shape of the frame, as a glyph. Shared with the camera's own
    /// orientation button so the row that sets it and the button that switches
    /// it are never showing two different pictures of the same choice.
    static func orientationIcon(_ orientation: Challenge.Orientation) -> String {
        switch orientation {
        case .portrait: "rectangle.portrait"
        case .landscape: "rectangle"
        case .square: "square"
        }
    }
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
                .foregroundStyle(Color.oneDayBrand)
                .frame(width: 42, height: 42)
                .background(Color.oneDayBrand.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

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
        .glassSurface(radius: OneDay.Radius.card, tint: .oneDayBrand)
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
                    TemplateCoverImage(
                        assetName: template.matchedCoverAssetName, fileURL: templateCoverURL)
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
                        .tint(Color.oneDayBrand)
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
                SectionLabel(text: Strings.theMoments(moments.count))
                Spacer()
                Button {
                    withAnimation(OneDay.Motion.soft) { momentsExpanded.toggle() }
                } label: {
                    Label(
                        momentsExpanded ? Strings.hideMoments : Strings.reviewMoments,
                        systemImage: momentsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.oneDayBrand)
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
                                    .foregroundStyle(Color.oneDayBrand)
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
                .tint(Color.oneDayBrand)

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
                    accent: .oneDayBrand,
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

            // No faces here. A room that hasn't been created yet has nobody in
            // it; borrowing names from the user's other rooms made the picker
            // claim a membership that doesn't exist. `roomExplainer` below says
            // what's actually true instead.
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
                    icon: Self.orientationIcon(orientation),
                    title: Strings.orientationRow,
                    accent: .oneDayMint
                ) {
                    PillSelector(
                        options: [
                            .init(value: Challenge.Orientation.portrait, label: Strings.orientationPortrait),
                            .init(value: Challenge.Orientation.landscape, label: Strings.orientationLandscape),
                            .init(value: Challenge.Orientation.square, label: Strings.orientationSquare),
                        ],
                        selection: $orientation,
                        compact: true)
                        // Three pills where there were two, and the labels are
                        // wider in Chinese than in English.
                        .frame(width: 236)
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
