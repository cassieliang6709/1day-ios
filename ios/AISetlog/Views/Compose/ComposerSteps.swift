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
    /// 「AI 帮我写」: a sentence about today in, prompts out.
    let onBuildOwn: () -> Void
    /// 「自己写」: the same page, starting in the first prompt row.
    var onWriteOwn: () -> Void = {}
    /// A poster tap adopts that script and opens the settings page. It used to
    /// create the story outright; see this type's note.
    let onChoose: (ChallengeTemplate) -> Void
    let onEdit: (ChallengeTemplate) -> Void
    let onDelete: (ChallengeTemplate) -> Void
    /// Where a template's own cover picture lives, asked of the store rather
    /// than looked up here — this layer doesn't know about Documents.
    var coverURL: (ChallengeTemplate) -> URL? = { _ in nil }

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system
    /// 一日 / 七日 / 我写过的 live behind 更多模板 as of 1.5, closed until asked.
    @State private var showsTemplates = false

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

                // 1.5: three ways in, and templates are the fourth, folded.
                // 按时间拍 leads because it asks for nothing — no prompts to
                // think up — which is the point of the camera-first app.
                byTimeEntry

                HStack(spacing: 10) {
                    smallEntry(
                        title: Strings.writeOwnTitle, lead: Strings.writeOwnLead,
                        symbol: "pencil.line", id: "write-own-entry", action: onWriteOwn)
                    smallEntry(
                        title: Strings.aiWriteTitle, lead: Strings.aiWriteLead,
                        symbol: "sparkles", id: "custom-prompts-entry", action: onBuildOwn)
                }
                // Same height whichever lead wraps.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)

                moreTemplatesHeader
                    .padding(.top, 8)

                if showsTemplates {
                    PillSelector(
                        options: [
                            .init(value: TemplateRack.oneDay, label: Strings.modeOneDay),
                            .init(value: TemplateRack.sevenDay, label: Strings.modeSevenDay),
                            .init(value: TemplateRack.custom, label: Strings.rackCustom),
                        ],
                        selection: $rack,
                        compact: true)
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("composer-rack")

                    grid
                }
            }
            .animation(OneDay.Motion.soft, value: showsTemplates)
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
                        // The poster is the only way to the settings page now
                        // that the gear is gone, so a test needs to be able to
                        // find one without knowing which rack it is on.
                        .accessibilityIdentifier("poster-tile")
                }
            }
            .padding(.horizontal, 20)

        }
    }

    /// 按时间拍: no prompts, the day filmed as it happens. Opens the same
    /// settings page a poster does, with the time-only script adopted.
    private var byTimeEntry: some View {
        Button {
            if let byTime = oneDayBuiltins.first(where: \.isTimeOnly) { onChoose(byTime) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(OneDay.onBrand)
                    .frame(width: 50, height: 50)
                    .background(.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.byTimeEntryTitle)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                    Text(Strings.byTimeEntryLead)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(OneDay.onBrand)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(OneDay.onBrand.opacity(0.75))
            }
            .padding(16)
            .background(OneDay.brandHorizontal, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .oneDayGlow(.oneDayBrand, strength: 0.7)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("by-time-entry")
        .padding(.horizontal, 20)
    }

    private func smallEntry(
        title: String, lead: String, symbol: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(OneDay.brandText)
                    .frame(width: 38, height: 38)
                    .background(Color.oneDayBrand.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Text(lead)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .background(OneDay.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(OneDay.hairline, lineWidth: 1))
            .oneDaySoftShadow(strength: 0.6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    private var moreTemplatesHeader: some View {
        Button {
            withAnimation(OneDay.Motion.soft) { showsTemplates.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(Strings.moreTemplates)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .rotationEffect(.degrees(showsTemplates ? 90 : 0))
                Spacer()
            }
            .foregroundStyle(OneDay.inkSoft)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("more-templates")
        .accessibilityAddTraits(showsTemplates ? .isSelected : [])
        .padding(.horizontal, 20)
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
                        .foregroundStyle(OneDay.onBrand)
                    Text(Strings.customPromptsLead)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.onBrand.opacity(0.88))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(OneDay.onBrand.opacity(0.75))
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
    /// The camera the whole story films with. Replaces the old length and
    /// frame rows: a camera already decides the shape of the picture.
    @Binding var cameraStyle: CameraStyle
    /// The story's moments, as raw display strings once touched. Editable here
    /// so you can see exactly what you'll be asked to film before committing —
    /// picking a mood shouldn't mean accepting seven prompts sight unseen.
    @Binding var moments: [String]
    let isOneDay: Bool
    let isTimeOnly: Bool

    @FocusState private var titleFocused: Bool
    /// Which moment row has the keyboard, so return walks down the list and a
    /// freshly added row is ready to type into.
    @FocusState private var focusedMoment: Int?
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
                .foregroundStyle(OneDay.brandText)
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
            // Fixed: the company picker below already says who's filming, and
            // a title that renamed itself on that toggle read as a new screen.
            Text(Strings.composerSetupStep)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
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
                        .submitLabel(isTimeOnly ? .done : .next)
                        .onSubmit(focusFirstMoment)
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
                        .foregroundStyle(OneDay.brandText)
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

                        if moments.count < StoryMoments.maxCount {
                            Divider().overlay(OneDay.hairline).padding(.leading, 38)
                            Button {
                                withAnimation(OneDay.Motion.soft) { moments.append("") }
                                let newRow = moments.count - 1
                                DispatchQueue.main.async { focusedMoment = newRow }
                            } label: {
                                Label(Strings.addMoment, systemImage: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(OneDay.brandText)
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
                .focused($focusedMoment, equals: index)
                .submitLabel(index == moments.count - 1 ? .done : .next)
                .onSubmit {
                    focusedMoment = index < moments.count - 1 ? index + 1 : nil
                }

            if moments.count > 2 {
                Button {
                    withAnimation(OneDay.Motion.soft) {
                        guard moments.indices.contains(index) else { return }
                        moments.remove(at: index)
                    }
                } label: {
                    // The glyph stays small; the hit area is a full 44pt so a
                    // thumb aimed at it doesn't land in the text field instead.
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(OneDay.inkFaint)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.deleteMoment)
            }
        }
        .padding(.vertical, 7)
    }

    /// Return on the name goes to the first moment — opening the list first if
    /// it's collapsed, since there's nothing to focus in a summary.
    private func focusFirstMoment() {
        guard !isTimeOnly, !moments.isEmpty else { return }
        withAnimation(OneDay.Motion.soft) { momentsExpanded = true }
        // Next runloop: the rows don't exist until the expansion has rendered,
        // and focusing a field that isn't there yet is silently dropped.
        DispatchQueue.main.async { focusedMoment = 0 }
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
                    // The drawn label is a stack of three things, so its
                    // accessibility label is all three concatenated and an
                    // exact-string lookup cannot find it.
                    .accessibilityIdentifier("company-solo")

                CompanyOption(
                    icon: "person.2.fill",
                    title: Strings.withFriends,
                    caption: Strings.createWithFriendsCaption,
                    accent: .oneDayLavender,
                    isOn: withFriends
                ) { withFriends = true }
                    .accessibilityIdentifier("company-with-friends")
            }

            // No faces here. A room that hasn't been created yet has nobody in
            // it; borrowing names from the user's other rooms made the picker
            // claim a membership that doesn't exist. `roomExplainer` below says
            // what's actually true instead.
        }
    }


    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: Strings.pickCamera)
            HStack(alignment: .top, spacing: 10) {
                ForEach(CameraStyle.selectable) { style in
                    CameraOption(style: style, isOn: cameraStyle == style) {
                        cameraStyle = style
                    }
                    .accessibilityIdentifier("camera-option-\(style.rawValue)")
                }
            }
        }
    }
}

/// One camera on the setup page: the picture's shape, tinted roughly the way
/// that camera grades, with its name and what it looks like underneath.
private struct CameraOption: View {
    let style: CameraStyle
    let isOn: Bool
    let action: () -> Void

    private var shape: CGFloat { style.aspectRatio(for: .portrait) ?? 3 / 4 }

    private var swatch: [Color] {
        switch style {
        case .camcorder: [Color(red: 0.42, green: 0.55, blue: 0.68), Color(red: 0.2, green: 0.26, blue: 0.34)]
        case .film: [Color(red: 0.98, green: 0.72, blue: 0.42), Color(red: 0.6, green: 0.34, blue: 0.2)]
        case .instant: [Color(red: 0.95, green: 0.88, blue: 0.8), Color(red: 0.74, green: 0.68, blue: 0.62)]
        case .standard: [.gray, .gray]
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: style == .instant ? 3 : 8, style: .continuous)
                    .fill(LinearGradient(colors: swatch, startPoint: .top, endPoint: .bottom))
                    .aspectRatio(shape, contentMode: .fit)
                    .padding(style == .instant ? 5 : 0)
                    .padding(.bottom, style == .instant ? 10 : 0)
                    .background(style == .instant ? Color.white : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        Image(systemName: style.symbolName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(height: 96)
                Text(style.displayName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Text(style.setupCaption)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(OneDay.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isOn ? Color.oneDayBrand : OneDay.hairline, lineWidth: isOn ? 2.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
