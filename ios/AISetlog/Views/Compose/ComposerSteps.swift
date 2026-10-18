import SwiftUI

/// The pieces of `StoryComposerView`'s one page. Stateless — the composer owns
/// every choice; these just render it.
///
/// 1.5 shape, top to bottom: 拍什么 (写今天的清单 / 从模板开始 / 按时间拍),
/// 名字, 自己拍 / 和朋友一起拍, 用哪台相机拍, and a single pinned 开始拍.
/// The templates themselves live on `TemplatesPage`, pushed from 从模板开始.
/// Every section uses the same 16pt side margin; `ComposerLayout.margin` is
/// that number.

enum ComposerLayout {
    static let margin: CGFloat = 16
    static let rowRadius: CGFloat = 16
}

// MARK: - 拍什么

/// Where the story's prompts come from.
enum ComposerEntry: Hashable {
    /// 写今天的清单 — the list editor, typed or drafted by AI. A template
    /// fills the same list.
    case writeList
    /// 不写，按时间拍 — no prompts at all.
    case byTime
}

/// The three ways in, as three rows. 从模板开始 sits between the other two
/// because a template *is* a written list — just one somebody wrote earlier —
/// so it belongs next to 写今天的清单 rather than under the page as its own
/// section. It's a row like the others, not a grid: the grid used to be here
/// and pushed the name and camera off the first screen.
///
/// Only one row is checked at a time, even though a template also fills the
/// list behind 写今天的清单: the check says where the list came from, and the
/// 清单 · N 项 row under the name is the way into the list either way.
struct WhatToFilmSection: View {
    let entry: ComposerEntry
    /// The chosen template's name, or nil when none is chosen.
    let templateName: String?
    /// How many templates the page behind 从模板开始 holds.
    let templateCount: Int
    let onWriteList: () -> Void
    let onTemplates: () -> Void
    let onByTime: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: Strings.composerWhatToFilm)
            ChoiceRow(
                title: Strings.composerWriteList, lead: Strings.composerWriteListLead,
                isOn: entry == .writeList && templateName == nil,
                opensPage: true, icon: "checklist", action: onWriteList)
                .accessibilityIdentifier("write-own-entry")
            ChoiceRow(
                title: Strings.listFromTemplate,
                lead: templateName.map(Strings.composerTemplateChosen)
                    ?? Strings.composerTemplateEntryLead(templateCount),
                isOn: templateName != nil,
                opensPage: true, icon: "square.grid.2x2.fill", action: onTemplates)
                .accessibilityIdentifier("templates-entry")
            ChoiceRow(
                title: Strings.composerByTimeTitle, lead: Strings.composerByTimeLead,
                isOn: entry == .byTime, icon: "alarm.fill", action: onByTime)
                .accessibilityIdentifier("by-time-entry")
        }
        .padding(.horizontal, ComposerLayout.margin)
    }
}

// MARK: - 拍几天

struct DaysSection: View {
    @Binding var days: Challenge.Mode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: Strings.composerHowManyDays)
            ChoiceRow(
                title: Strings.composerPlanOneDay, lead: Strings.composerPlanOneDayLead,
                isOn: days == .oneDay) { days = .oneDay }
                .accessibilityIdentifier("plan-one-day")
            ChoiceRow(
                title: Strings.composerPlanSevenDay, lead: Strings.composerPlanSevenDayLead,
                isOn: days == .sevenDay) { days = .sevenDay }
                .accessibilityIdentifier("plan-seven-day")
        }
        .padding(.horizontal, ComposerLayout.margin)
    }
}

/// One radio row: a check, a title, one line under it.
private struct ChoiceRow: View {
    let title: String
    let lead: String
    let isOn: Bool
    /// A chevron on the end: tapping opens a page, not just a selection.
    var opensPage = false
    /// A small picture for the choice: a checklist, a cute alarm clock.
    var icon: String? = nil
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .animation(OneDay.Motion.snap, value: isOn)
    }

    private var label: some View {
        HStack(spacing: 12) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isOn ? Color.oneDayBrand : OneDay.inkFaint)
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.oneDayBrand)
                    .symbolEffect(.bounce, value: isOn)
                    .frame(width: 36, height: 36)
                    .background(Color.oneDayBrand.opacity(0.12), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Text(lead)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if opensPage {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OneDay.inkFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(OneDay.surface, in: shape)
        .overlay(shape.strokeBorder(
            isOn ? Color.oneDayBrand : OneDay.hairline, lineWidth: isOn ? 1.5 : 1))
        .contentShape(shape)
    }
}

// MARK: - 模板

/// Every template on a page of its own, pushed from 从模板开始: the user's own
/// first (badged 我的), then the built-ins, two to a row.
///
/// Why a pushed page and not the grid that used to sit on 今天想拍什么 with a
/// 更多模板 sheet behind it: the inline row only ever had room for two cards,
/// so the grid was mostly a teaser for the sheet, and the sheet was a second
/// copy of the same grid with its own close button. Two places to pick a
/// template, one of them half a page long, on a page whose job is to answer
/// three short questions. Now the page keeps a single row that says what was
/// picked, and the picking happens here, with the system back button as the
/// way out when nothing is picked.
///
/// Choosing is the composer's `choose` unchanged — tapping the chosen one again
/// still lets go — and either way the page pops straight back, which is what
/// the sheet did on a tap too: the next thing to do (the name, 开始拍) is on
/// the page underneath.
struct TemplatesPage: View {
    let mine: [ChallengeTemplate]
    let builtIns: [ChallengeTemplate]
    let selectedTemplateID: UUID?
    let onChoose: (ChallengeTemplate) -> Void
    let onEdit: (ChallengeTemplate) -> Void
    let onDelete: (ChallengeTemplate) -> Void
    let coverURL: (ChallengeTemplate) -> URL?

    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var all: [(template: ChallengeTemplate, isMine: Bool)] {
        mine.map { ($0, true) } + builtIns.map { ($0, false) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(all, id: \.template.id) { tile($0.template, isMine: $0.isMine) }
            }
            .padding(ComposerLayout.margin)
        }
        .background(OneDay.canvas)
        .navigationTitle(Strings.composerTemplates)
        .navigationBarTitleDisplayMode(.inline)
        // The composer hides its bar (its own 关闭 bubble is the top row); this
        // page needs one for the back button and the title.
        .toolbar(.visible, for: .navigationBar)
    }

    private func tile(_ template: ChallengeTemplate, isMine: Bool) -> some View {
        TemplateTile(
            template: template,
            isMine: isMine,
            isSelected: template.id == selectedTemplateID,
            coverURL: coverURL(template),
            onSelect: {
                onChoose(template)
                dismiss()
            },
            // Edit and delete stay on the page: they're about the template, not
            // about this story, so neither one sends you back.
            onEdit: isMine ? { onEdit(template) } : nil,
            onDelete: isMine ? { onDelete(template) } : nil)
            .accessibilityIdentifier(isMine ? "saved-template-tile" : "poster-tile")
    }
}

private struct TemplateTile: View {
    let template: ChallengeTemplate
    let isMine: Bool
    let isSelected: Bool
    var coverURL: URL?
    let onSelect: () -> Void
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    /// "起床 · 咖啡…" — enough to recognise the day's shape at this size.
    private var subtitleText: String {
        guard let keys = template.momentKeys, !keys.isEmpty else { return template.displayBlurb }
        let head = keys.prefix(2).map { MomentCatalog.localize($0) }.joined(separator: " · ")
        return keys.count > 2 ? head + "…" : head
    }

    var body: some View {
        Button(action: onSelect) { card }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu {
                if let onEdit {
                    Button(Strings.editTemplate, systemImage: "pencil", action: onEdit)
                }
                if let onDelete {
                    Button(Strings.deleteTemplate, systemImage: "trash",
                           role: .destructive, action: onDelete)
                }
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            VStack(alignment: .leading, spacing: 2) {
                Text(template.displayName)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(1)
                Text(subtitleText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
        }
        .background(OneDay.surface, in: shape)
        .clipShape(shape)
        .contentShape(shape)
        .overlay(shape.strokeBorder(
            isSelected ? Color.oneDayBrand : OneDay.hairline, lineWidth: isSelected ? 2 : 1))
        .overlay(alignment: .topTrailing) { if isSelected { check } }
        .overlay(alignment: .topLeading) { if isMine { mineBadge } }
    }

    private var cover: some View {
        TemplateCoverImage(assetName: template.matchedCoverAssetName, fileURL: coverURL)
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .aspectRatio(2, contentMode: .fit)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var check: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.oneDayBrand)
            .padding(6)
    }

    private var mineBadge: some View {
        Text(Strings.composerMineBadge)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundStyle(OneDay.brandText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(OneDay.surface, in: Capsule())
            .padding(6)
    }
}

// MARK: - 名字, who's filming, which camera

/// The rest of the page: the story's name (with the list's summary row under
/// it), 自己拍 / 和朋友一起拍, and 用哪台相机拍.
struct SetupStep: View {
    let template: ChallengeTemplate?
    var templateCoverURL: URL?
    @Binding var title: String
    @Binding var titleEdited: Bool
    @Binding var withFriends: Bool
    @Binding var cameraStyle: CameraStyle
    let isOneDay: Bool
    /// Nil when the story films by time — then nothing shows under the name.
    let listCount: Int?
    let onOpenList: () -> Void

    @FocusState private var titleFocused: Bool
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

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

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            nameSection
            CompanySegment(withFriends: $withFriends)
            cameraSection
        }
        .padding(.horizontal, ComposerLayout.margin)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: Strings.composerName)
            nameField
            if let listCount {
                ListSummaryRow(count: listCount, action: onOpenList)
            }
        }
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            if let template {
                TemplateCoverImage(assetName: template.matchedCoverAssetName, fileURL: templateCoverURL)
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
            }
            TextField("", text: $title, prompt: Text(Strings.titlePrompt(oneDay: isOneDay)))
                .font(.system(size: 16.5, weight: .bold, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .tint(Color.oneDayBrand)
                .focused($titleFocused)
                .submitLabel(.done)
                .onChange(of: title) { _, _ in
                    if titleFocused { titleEdited = true }
                }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(OneDay.surface, in: RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous)
            .strokeBorder(OneDay.hairline, lineWidth: 1))
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

/// 清单 · 5 项 > — the list, folded to one row. Opens the editor.
private struct ListSummaryRow: View {
    let count: Int
    let action: () -> Void

    private var text: String {
        count > 0 ? Strings.composerListSummary(count) : Strings.composerListEmpty
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OneDay.brandText)
                Text(text)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(count > 0 ? OneDay.ink : OneDay.inkSoft)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OneDay.inkFaint)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(OneDay.surface, in: RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous)
                .strokeBorder(OneDay.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("composer-list-summary")
    }
}

/// 自己拍 | 和朋友一起拍 — a two-part segmented control. Built by hand so each
/// half can carry its own accessibility id.
private struct CompanySegment: View {
    @Binding var withFriends: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                segment(Strings.composerFilmSolo, isOn: !withFriends, id: "company-solo") {
                    withFriends = false
                }
                segment(Strings.composerFilmTogether, isOn: withFriends, id: "company-with-friends") {
                    withFriends = true
                }
            }
            .padding(3)
            .background(OneDay.inkFaint.opacity(0.14), in: Capsule())

            Text(withFriends ? Strings.createWithFriendsCaption : Strings.createByYourselfCaption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .padding(.leading, 4)
        }
        .animation(OneDay.Motion.snap, value: withFriends)
    }

    private func segment(_ title: String, isOn: Bool, id: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: isOn ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isOn ? OneDay.ink : OneDay.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    if isOn {
                        Capsule().fill(OneDay.surface).oneDaySoftShadow(strength: 0.5)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// One camera on the page: the camera itself as a little mascot, a corner
/// badge in the shape of its frame, its name and what it looks like.
private struct CameraOption: View {
    let style: CameraStyle
    let isOn: Bool
    let action: () -> Void

    private var shape: CGFloat { style.aspectRatio(for: .portrait) ?? 3 / 4 }
    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: ComposerLayout.rowRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                picture
                Text(style.displayName)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                Text(style.setupCaption)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
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
                isOn ? Color.oneDayBrand : OneDay.hairline, lineWidth: isOn ? 1.5 : 1))
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
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomTrailing) { frameBadge }
            .accessibilityHidden(true)
    }

    /// The frame's shape, drawn small: 3:4 or 2:3, upright.
    private var frameBadge: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .strokeBorder(OneDay.inkSoft, lineWidth: 1.5)
            .aspectRatio(shape, contentMode: .fit)
            .frame(height: 16)
            .padding(.trailing, 4)
    }
}
