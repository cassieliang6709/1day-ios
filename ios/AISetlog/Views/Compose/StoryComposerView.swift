import SwiftUI

/// Making a story, on one page (1.5).
///
/// Top to bottom: 拍什么 (写今天的清单 / 按时间拍), 拍几天, 模板 (the user's
/// own first, then that length's built-ins), 名字, 自己拍 / 和朋友一起拍,
/// 用哪台相机拍, and one pinned 开始拍.
///
/// 写今天的清单 opens the list editor (`GuidedMomentsView`) — typed by hand or
/// drafted by AI from one sentence, in the same page. A template fills the
/// same list; the page shows it folded to one 清单 · N 项 row.
struct StoryComposerView: View {
    var onCreate: (UUID) -> Void = { _ in }
    /// How to leave. Nil means "I was presented, dismiss me" — the sheet path.
    /// `RootShellView` passes a closure instead, because as the 新建 surface
    /// this view has no presentation to dismiss and `dismiss()` is a no-op.
    var onClose: (() -> Void)? = nil
    /// Opens with 和朋友一起 already chosen — the 朋友 tab's invite button.
    /// Only the starting value; the cards on the page still work.
    var startsWithFriends = false

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    /// 写今天的清单 or 按时间拍. Choosing a template switches this to the list.
    @State private var entry: ComposerEntry = .byTime
    /// A built-in poster or one of the user's own templates, when one is chosen.
    @State private var templateID: UUID?
    @State private var days: Challenge.Mode = .oneDay
    /// No longer asked (1.5): with hold-to-record a length is only a ceiling,
    /// and the camera you pick already decides the frame's shape.
    private let clipLength: Challenge.ClipLength = .scene
    private let orientation: Challenge.Orientation = .portrait
    @State private var cameraStyle: CameraStyle = CameraStyle.defaultCamera
    @State private var withFriends = false
    /// 存为我的模板, asked in the list editor and done when the story starts,
    /// once the name is known.
    @State private var savesList = true
    @State private var title = ""
    /// Set once the user edits the name, so switching templates stops
    /// overwriting what they typed.
    @State private var titleEdited = false
    /// The story's moments. Seeded from the chosen template, then replaced
    /// wholesale by whatever the list editor hands back.
    @State private var moments: [String] = []
    @State private var showGuided = false
    @State private var creating = false
    @State private var errorText: String?
    @State private var showSignIn = false
    @State private var editingTemplate: ChallengeTemplate?

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var oneDayPosters: [ChallengeTemplate] {
        ChallengeTemplate.oneDayBuiltins.filter { !$0.isTimeOnly }
    }

    private var sevenDayPosters: [ChallengeTemplate] {
        ChallengeTemplate.sevenDayBuiltins
    }

    private var allTemplates: [ChallengeTemplate] {
        ChallengeTemplate.oneDayBuiltins + sevenDayPosters + store.customTemplates
    }

    /// The template backing the story: the chosen one, or the time-only
    /// built-in behind 按时间拍. Nil for a list written by hand.
    private var selected: ChallengeTemplate? {
        if let templateID {
            return allTemplates.first { $0.id == templateID }
        }
        return entry == .byTime ? ChallengeTemplate.liveWithMe : nil
    }

    private var isTimeOnly: Bool { selected?.isTimeOnly == true }

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 1)

            VStack(spacing: 0) {
                topBar
                page
                footer
            }
        }
        .sheet(isPresented: $showGuided) {
            GuidedMomentsView(
                initialMoments: moments,
                allowsSaving: templateID == nil,
                savesToLibrary: savesList,
                onDone: applyCustomDraft)
        }
        .sheet(isPresented: $showSignIn) {
            SignInView { createSharedRoom() }
                .presentationDetents([.medium])
        }
        .sheet(item: $editingTemplate) { template in
            BuildTemplateView(
                template: template,
                coverURL: store.coverURL(for: template)
            ) { updated, coverImageData in
                store.updateCustomTemplate(updated, coverImageData: coverImageData)
            }
        }
        .onAppear {
            if startsWithFriends { withFriends = true }
            syncTitleToTemplate()
        }
        // Switching to solo answers "sign into iCloud" all by itself, so the
        // warning shouldn't outlive the choice that caused it.
        .onChange(of: withFriends) { _, _ in errorText = nil }
        .onChange(of: days) { _, newDays in daysChanged(to: newDays) }
    }

    // MARK: - Layout

    private var topBar: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: "xmark") { leave() }
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, ComposerLayout.margin - 4)
        .padding(.top, 8)
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(Strings.newStoryQuestion)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .accessibilityIdentifier("composer-question")
                    .padding(.horizontal, ComposerLayout.margin)
                WhatToFilmSection(
                    entry: entry, onWriteList: openList, onByTime: chooseByTime)
                DaysSection(days: $days)
                templates
                setup
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var templates: some View {
        TemplatesSection(
            mine: store.customTemplates,
            builtIns: days == .oneDay ? oneDayPosters : sevenDayPosters,
            selectedTemplateID: templateID,
            onChoose: choose,
            onEdit: { editingTemplate = $0 },
            onDelete: deleteTemplate,
            coverURL: { store.coverURL(for: $0) })
    }

    private var setup: some View {
        SetupStep(
            template: selected,
            templateCoverURL: selected.flatMap { store.coverURL(for: $0) },
            title: $title,
            titleEdited: $titleEdited,
            withFriends: $withFriends,
            cameraStyle: $cameraStyle,
            isOneDay: days == .oneDay,
            listCount: entry == .writeList ? resolvedMoments?.count ?? 0 : nil,
            onOpenList: openList)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            // Above the button: the reason a tap did nothing has to be on
            // screen when the tap happens.
            if let errorText {
                footerNote(errorText, systemImage: "exclamationmark.circle.fill", color: .red)
            }
            if trimmedTitle.isEmpty {
                footerNote(Strings.storyNameNeeded, color: .secondary)
                    .accessibilityIdentifier("composer-name-needed")
            }
            startButton
        }
        .padding(.horizontal, ComposerLayout.margin)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .animation(OneDay.Motion.soft, value: errorText)
    }

    private func footerNote(_ text: String, systemImage: String? = nil, color: Color) -> some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(color)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private var startButton: some View {
        Button(action: start) {
            HStack(spacing: 8) {
                if creating {
                    ProgressView().tint(.white)
                } else {
                    Text(withFriends ? Strings.createRoom : Strings.startFilmingCTA)
                    Image(systemName: "sparkles")
                }
            }
        }
        .buttonStyle(.primaryAction)
        .disabled(!canStart)
        .opacity(canStart ? 1 : 0.55)
        .accessibilityIdentifier("composer-start")
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canStart: Bool {
        !trimmedTitle.isEmpty && !creating && (isTimeOnly || resolvedMoments?.isEmpty == false)
    }

    // MARK: - Choices

    private func chooseByTime() {
        entry = .byTime
        templateID = nil
        syncTitleToTemplate()
    }

    private func openList() {
        showGuided = true
    }

    /// A template fills the list. Tapping the chosen one again lets it go.
    private func choose(_ template: ChallengeTemplate) {
        if templateID == template.id {
            deselectTemplate()
            return
        }
        entry = .writeList
        templateID = template.id
        syncTitleToTemplate()
    }

    /// Back to an empty list: the template's moments and name were its, not
    /// the user's.
    private func deselectTemplate() {
        let wasNamedByIt = !titleEdited
        templateID = nil
        moments = []
        if wasNamedByIt { title = "" }
    }

    /// A built-in poster belongs to one length; switching away from it drops
    /// it rather than making a seven-day story from a one-day script.
    private func daysChanged(to newDays: Challenge.Mode) {
        let posters = newDays == .oneDay ? oneDayPosters : sevenDayPosters
        let isOtherLengthPoster = (oneDayPosters + sevenDayPosters)
            .contains { $0.id == templateID } && !posters.contains { $0.id == templateID }
        if isOtherLengthPoster { deselectTemplate() }
        syncTitleToTemplate()
    }

    private func deleteTemplate(_ template: ChallengeTemplate) {
        let wasSelected = templateID == template.id
        store.deleteCustomTemplate(template)
        if wasSelected { deselectTemplate() }
    }

    /// What the list editor wrote, applied to this story. The name only
    /// follows the AI's suggestion while the user hasn't typed one.
    private func applyCustomDraft(_ draft: CustomStoryDraft) {
        entry = .writeList
        moments = draft.moments
        savesList = draft.savesToLibrary
        errorText = nil
        if !titleEdited, templateID == nil {
            title = draft.suggestedName ?? (isTitleFromByTime ? "" : title)
        }
    }

    /// The name 按时间拍 gave the story, which means nothing for a list.
    private var isTitleFromByTime: Bool {
        let byTime = ChallengeTemplate.liveWithMe.displayName
        return title == byTime || title == Strings.fullTitle7Days(byTime)
    }

    /// 存为我的模板: a hand-written list becomes one of the user's templates,
    /// under the name the story starts with.
    private func saveListIfAsked() {
        guard entry == .writeList, templateID == nil, savesList,
              let keys = resolvedMoments, !keys.isEmpty else { return }
        _ = store.addCustomTemplate(
            ChallengeTemplate(
                name: LocalizedText(en: trimmedTitle, zh: trimmedTitle),
                momentKeys: keys.map { MomentCatalog.key(forDisplay: $0) ?? $0 },
                isCustom: true),
            coverImageData: nil)
    }

    // MARK: - Actions

    /// Leaving, whichever way this view got on screen. See `onClose`.
    private func leave() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func start() {
        // `dismiss()` isn't instant, so a second tap inside the closing
        // animation used to insert a second story.
        guard canStart else { return }
        if withFriends {
            if account.isSignedIn { createSharedRoom() } else { showSignIn = true }
            return
        }
        creating = true
        let challenge = store.create(
            title: trimmedTitle,
            mode: days,
            clipLength: clipLength,
            orientation: orientation,
            cameraStyle: cameraStyle,
            templateName: selected?.identityKey,
            momentTitles: resolvedMoments)
        saveListIfAsked()
        leave()
        onCreate(challenge.id)
    }

    private func createSharedRoom() {
        creating = true
        errorText = nil
        Task {
            defer { creating = false }
            do {
                let challenge = try await store.createSharedRoom(
                    title: trimmedTitle,
                    mode: days,
                    clipLength: clipLength,
                    orientation: orientation,
                    cameraStyle: cameraStyle,
                    templateName: selected?.identityKey,
                    momentTitles: resolvedMoments)
                saveListIfAsked()
                leave()
                onCreate(challenge.id)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Derived state

    /// Keeps the story name in step with the chosen script until the user
    /// takes the name over.
    private func syncTitleToTemplate() {
        guard let selected else { return }
        if !titleEdited {
            title = days == .sevenDay
                ? Strings.fullTitle7Days(selected.displayName)
                : selected.displayName
        }
        // Moments always follow the template: picking one *is* the request for
        // its prompts. The name doesn't, because you typed that.
        moments = selected.momentKeys ?? []
    }

    /// Blank rows are dropped; an entirely empty list falls back to the
    /// template's own moments so a story can never be created with none.
    private var resolvedMoments: [String]? {
        if isTimeOnly { return nil }
        let cleaned = moments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? selected?.momentKeys : cleaned
    }
}
