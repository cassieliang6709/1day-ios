import SwiftUI

/// The pieces of `StoryComposerView`'s one page. Stateless — the composer owns
/// every choice; these just render it.
///
/// 1.5 shape, top to bottom: 今天拍什么 (three equal ways in), 拍几天 (one day
/// or seven, with that length's templates as an optional strip), 之前做过的
/// (the user's own saved sets), then the story's name, 谁来拍 and 用哪台相机拍,
/// and a single 开始拍 at the bottom. There used to be a second 设置 sheet
/// behind every choice; everything it asked is on this page now.

// MARK: - 今天拍什么

/// Where the story's prompts come from.
enum ComposerEntry: Hashable {
    /// 自己写 — the guided page, cursor in the first row.
    case writeOwn
    /// AI 帮我写 — the guided page, starting on its sentence about today.
    case aiWrite
    /// 不写，按时间拍 — no prompts at all.
    case byTime
}

/// Sections 1–3 of the page: how the prompts get written, how many days, and
/// the sets the user has made before.
struct MoodStep: View {
    /// Nil when a poster or a saved set is what's chosen instead.
    let entry: ComposerEntry?
    @Binding var days: Challenge.Mode
    let oneDayPosters: [ChallengeTemplate]
    let sevenDayPosters: [ChallengeTemplate]
    let customTemplates: [ChallengeTemplate]
    let selectedTemplateID: UUID?
    let onWriteOwn: () -> Void
    let onBuildOwn: () -> Void
    let onByTime: () -> Void
    let onChoose: (ChallengeTemplate) -> Void
    let onEdit: (ChallengeTemplate) -> Void
    let onDelete: (ChallengeTemplate) -> Void
    var coverURL: (ChallengeTemplate) -> URL? = { _ in nil }

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            EntryCards(
                entry: entry, onWriteOwn: onWriteOwn,
                onBuildOwn: onBuildOwn, onByTime: onByTime)
                .padding(.horizontal, 20)

            DaysSection(
                days: $days,
                oneDayPosters: oneDayPosters,
                sevenDayPosters: sevenDayPosters,
                selectedTemplateID: selectedTemplateID,
                onChoose: onChoose,
                coverURL: coverURL)

            if !customTemplates.isEmpty {
                madeBefore
            }
        }
    }

    /// The user's own sets, as a strip. Hidden until there is one.
    private var madeBefore: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: Strings.composerMadeBefore)
                .padding(.horizontal, 20)
            TemplateStrip(
                templates: customTemplates,
                selectedTemplateID: selectedTemplateID,
                tileID: "saved-template-tile",
                onChoose: onChoose,
                onEdit: onEdit,
                onDelete: onDelete,
                coverURL: coverURL)
        }
        .accessibilityIdentifier("made-before")
    }
}

/// 自己写 / AI 帮我写 / 不写，按时间拍 — three equal cards in one row.
private struct EntryCards: View {
    let entry: ComposerEntry?
    let onWriteOwn: () -> Void
    let onBuildOwn: () -> Void
    let onByTime: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: Strings.composerWhatToFilm)
            HStack(spacing: 10) {
                EntryCard(
                    title: Strings.writeOwnTitle, lead: Strings.writeOwnLead,
                    symbol: "pencil.line", isOn: entry == .writeOwn, action: onWriteOwn)
                    .accessibilityIdentifier("write-own-entry")
                EntryCard(
                    title: Strings.aiWriteTitle, lead: Strings.aiWriteLead,
                    symbol: "sparkles", isOn: entry == .aiWrite, action: onBuildOwn)
                    .accessibilityIdentifier("custom-prompts-entry")
                EntryCard(
                    title: Strings.composerByTimeTitle, lead: Strings.composerByTimeLead,
                    symbol: "clock.fill", isOn: entry == .byTime, action: onByTime)
                    .accessibilityIdentifier("by-time-entry")
            }
            // Same height whichever lead wraps.
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EntryCard: View {
    let title: String
    let lead: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                icon
                Text(title)
                    .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lead)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(OneDay.surface, in: shape)
            .overlay(shape.fill(Color.oneDayBrand.opacity(isOn ? 0.1 : 0)))
            .overlay(shape.strokeBorder(
                isOn ? Color.oneDayBrand : OneDay.hairline, lineWidth: isOn ? 2.5 : 1))
            .oneDaySoftShadow(strength: isOn ? 0.8 : 0.5)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(OneDay.Motion.snap, value: isOn)
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isOn ? OneDay.onBrand : OneDay.brandText)
            .frame(width: 34, height: 34)
            .background(
                isOn ? AnyShapeStyle(Color.oneDayBrand) : AnyShapeStyle(Color.oneDayBrand.opacity(0.18)),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - 拍几天

/// Two rows that say what each length means, instead of 一日 / 七日 pills.
/// The chosen one opens its templates underneath; picking one is optional.
private struct DaysSection: View {
    @Binding var days: Challenge.Mode
    let oneDayPosters: [ChallengeTemplate]
    let sevenDayPosters: [ChallengeTemplate]
    let selectedTemplateID: UUID?
    let onChoose: (ChallengeTemplate) -> Void
    let coverURL: (ChallengeTemplate) -> URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: Strings.composerHowManyDays)
                .padding(.horizontal, 20)
            row(.oneDay, title: Strings.composerPlanOneDay,
                lead: Strings.composerPlanOneDayLead, id: "plan-one-day")
            if days == .oneDay { strip(oneDayPosters) }
            row(.sevenDay, title: Strings.composerPlanSevenDay,
                lead: Strings.composerPlanSevenDayLead, id: "plan-seven-day")
            if days == .sevenDay { strip(sevenDayPosters) }
        }
        .animation(OneDay.Motion.soft, value: days)
    }

    private func row(_ mode: Challenge.Mode, title: String, lead: String, id: String) -> some View {
        DayRow(title: title, lead: lead, isOn: days == mode) { days = mode }
            .accessibilityIdentifier(id)
            .padding(.horizontal, 20)
    }

    private func strip(_ posters: [ChallengeTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Strings.composerOptionalTemplates)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.inkFaint)
                .padding(.horizontal, 24)
            TemplateStrip(
                templates: posters,
                selectedTemplateID: selectedTemplateID,
                tileID: "poster-tile",
                onChoose: onChoose,
                coverURL: coverURL)
        }
        .padding(.bottom, 4)
        .transition(.opacity)
    }
}

private struct DayRow: View {
    let title: String
    let lead: String
    let isOn: Bool
    let action: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isOn ? Color.oneDayBrand : OneDay.inkFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                    Text(lead)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(OneDay.surface, in: shape)
            .overlay(shape.strokeBorder(
                isOn ? Color.oneDayBrand : OneDay.hairline, lineWidth: isOn ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A horizontal row of poster tiles.
private struct TemplateStrip: View {
    let templates: [ChallengeTemplate]
    let selectedTemplateID: UUID?
    let tileID: String
    let onChoose: (ChallengeTemplate) -> Void
    var onEdit: ((ChallengeTemplate) -> Void)?
    var onDelete: ((ChallengeTemplate) -> Void)?
    let coverURL: (ChallengeTemplate) -> URL?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 10) {
                ForEach(templates) { template in
                    tile(template)
                }
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    private func tile(_ template: ChallengeTemplate) -> some View {
        PromptTemplateTile(
            template: template,
            isSelected: template.id == selectedTemplateID,
            coverURL: coverURL(template),
            onSelect: { onChoose(template) },
            onEdit: onEdit.map { edit in { edit(template) } },
            onDelete: onDelete.map { delete in { delete(template) } })
            .frame(width: 150)
            .accessibilityIdentifier(tileID)
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

// MARK: - The story, who's filming, which camera

/// The rest of the page: the story's name and moments, then 谁来拍 and
/// 用哪台相机拍. Not its own screen any more — it sits under `MoodStep` in
/// the composer's single scroll.
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
    /// so you can see exactly what you'll be asked to film before committing.
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
        VStack(alignment: .leading, spacing: 24) {
            storySection
            companyPicker
            setupCard
        }
        .padding(.horizontal, 20)
        .animation(OneDay.Motion.soft, value: withFriends)
    }

    private var storySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: Strings.composerThisStory)
            nameField
            if isTimeOnly {
                timeOnlyCard
            } else {
                momentsCard
            }
        }
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

/// One camera on the page: the camera itself as a little mascot, a corner
/// badge in the shape of its frame, its name and what it looks like.
private struct CameraOption: View {
    let style: CameraStyle
    let isOn: Bool
    let action: () -> Void

    private var shape: CGFloat { style.aspectRatio(for: .portrait) ?? 3 / 4 }
    private var card: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                picture
                Text(style.displayName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Text(style.setupCaption)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(OneDay.surface, in: card)
            .overlay(card.fill(Color.oneDayBrand.opacity(isOn ? 0.08 : 0)))
            .overlay(card.strokeBorder(
                isOn ? Color.oneDayBrand : OneDay.hairline, lineWidth: isOn ? 2.5 : 1))
            .contentShape(card)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var picture: some View {
        Image(style.imageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: 78)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomTrailing) { frameBadge }
            .accessibilityHidden(true)
    }

    /// The frame's shape, drawn small: 3:4 or 2:3, upright.
    private var frameBadge: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .strokeBorder(OneDay.inkSoft, lineWidth: 1.5)
            .aspectRatio(shape, contentMode: .fit)
            .frame(height: 18)
            .padding(.trailing, 4)
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
