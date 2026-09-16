import SwiftUI

/// Making a story: one screen, one decision.
///
/// It was two screens and eight controls — 1/2 选拍法 with a style pill, a
/// mode pill and a poster grid, then 2/2 设置故事 with a name, a moment list, a
/// company picker and two capture rows — and seven of the eight already had
/// the right default. Now the rack of posters *is* the form: tapping one
/// creates the story with those defaults and goes straight to filming, and the
/// gear on a poster's corner opens everything the second screen used to ask,
/// for the person who actually wants to change something.
struct StoryComposerView: View {
    var onCreate: (UUID) -> Void = { _ in }

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    /// Which shelf of posters is showing. Purely a filter — the story's style
    /// and mode come from the poster that gets tapped.
    @State private var rack: TemplateRack = .oneDay
    /// Style, template and mode as one value — see `ComposerSelection` for why
    /// the style can't be inferred from the template.
    @State private var selection = ComposerSelection.initial(
        oneDay: ChallengeTemplate.oneDayBuiltins)
    @State private var clipLength: Challenge.ClipLength = .tiny
    @State private var orientation: Challenge.Orientation = .portrait
    @State private var withFriends = false
    @State private var title = ""
    /// Set once the user edits the name, so switching templates stops
    /// overwriting what they typed.
    @State private var titleEdited = false
    /// The story's moments. Seeded from the chosen template, then editable —
    /// and replaced wholesale by the guided flow.
    @State private var moments: [String] = []
    @State private var isCustomPromptStory = false
    @State private var showGuided = false
    /// The old step 2, now a sheet behind a poster's gear.
    @State private var showSetup = false
    @State private var creating = false
    @State private var errorText: String?
    @State private var showSignIn = false
    @State private var editingTemplate: ChallengeTemplate?

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    private var oneDayTemplates: [ChallengeTemplate] {
        ChallengeTemplate.oneDayBuiltins + store.customTemplates
    }

    private var sevenDayTemplates: [ChallengeTemplate] {
        ChallengeTemplate.sevenDayBuiltins
    }

    private var allTemplates: [ChallengeTemplate] {
        oneDayTemplates + sevenDayTemplates
    }

    private var mode: Challenge.Mode { selection.mode }

    private var selected: ChallengeTemplate? {
        guard let templateID = selection.templateID else { return nil }
        return allTemplates.first { $0.id == templateID }
    }

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 1)

            VStack(spacing: 0) {
                topBar

                MoodStep(
                    oneDayBuiltins: ChallengeTemplate.oneDayBuiltins,
                    sevenDayTemplates: sevenDayTemplates,
                    customTemplates: store.customTemplates,
                    rack: $rack,
                    onBuildOwn: beginCustomPromptFlow,
                    onChoose: createFromPoster,
                    onSettings: openSettings,
                    onEdit: { editingTemplate = $0 },
                    onDelete: deleteTemplate,
                    coverURL: { store.coverURL(for: $0) })
            }
        }
        .sheet(isPresented: $showSetup) { setupSheet }
        .sheet(isPresented: $showSignIn) {
            SignInView { createSharedRoom() }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showGuided) {
            GuidedMomentsView(onDone: applyCustomDraft)
        }
        .sheet(item: $editingTemplate) { template in
            BuildTemplateView(
                template: template,
                coverURL: store.coverURL(for: template)
            ) { updated, coverImageData in
                store.updateCustomTemplate(updated, coverImageData: coverImageData)
            }
        }
        .onAppear(perform: syncTitleToTemplate)
        .onChange(of: selection.templateID) { _, newID in
            guard newID != nil else { return }
            isCustomPromptStory = false
            // `titleEdited` deliberately survives this. Zeroing it here made
            // the flag unreadable — every call site reached `syncTitleToTemplate`
            // with it false — so naming a story 我的搬家日 and then browsing to
            // another template silently replaced the name with the template's.
            syncTitleToTemplate()
        }
        // Switching to solo answers "sign into iCloud" all by itself, so the
        // warning shouldn't outlive the choice that caused it.
        .onChange(of: withFriends) { _, _ in errorText = nil }
        .onChange(of: selection.mode) { _, _ in
            guard !isCustomPromptStory else { return }
            selection.reconcileTemplate(
                oneDay: oneDayTemplates, sevenDay: sevenDayTemplates)
        }
    }

    // MARK: - Chrome

    /// Just the way out. There is no progress counter because there is no
    /// second step — `StepDots` reading `1/2` was itself telling people to
    /// expect another screen to fill in.
    private var topBar: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: "xmark") { dismiss() }
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    // MARK: - The settings sheet

    /// Everything the second screen used to ask, now optional: reached from a
    /// poster's gear, and the only place 一起拍 lives.
    private var setupSheet: some View {
        VStack(spacing: 0) {
            // No title of its own: `SetupStep` already leads with 设置, and two
            // headings stacked read as two screens.
            HStack {
                Spacer()
                IconBubble(systemName: "xmark") { showSetup = false }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, -6)

            SetupStep(
                template: selected,
                templateCoverURL: selected.flatMap { store.coverURL(for: $0) },
                title: $title,
                titleEdited: $titleEdited,
                withFriends: $withFriends,
                clipLength: $clipLength,
                orientation: $orientation,
                moments: $moments,
                isOneDay: mode == .oneDay,
                isTimeOnly: selection.style == .timeOnly)

            sheetFooter
        }
        .background(OneDayCanvas(seed: 3))
    }

    private var sheetFooter: some View {
        VStack(spacing: 10) {
            // Above the button, not at the bottom of the scroll: the reason a
            // tap did nothing has to be on screen when the tap happens.
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(Strings.storyNameNeeded)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("composer-name-needed")
            }

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
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .animation(OneDay.Motion.soft, value: errorText)
    }

    private var canStart: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !creating
    }

    // MARK: - Actions

    private func start() {
        let name = title.trimmingCharacters(in: .whitespaces)
        // `dismiss()` isn't instant, so a second tap inside the closing
        // animation used to insert a second story. The shared path had this
        // guard through `creating`; the solo path — the common one — didn't.
        guard !name.isEmpty, !creating else { return }
        if withFriends {
            if account.isSignedIn { createSharedRoom() } else { showSignIn = true }
        } else {
            creating = true
            let challenge = store.create(
                title: name,
                mode: mode,
                clipLength: clipLength,
                orientation: orientation,
                templateName: selected?.identityKey,
                momentTitles: resolvedMoments)
            // Closing the sheet first: dismissing the composer out from under
            // an open sheet leaves the sheet animating over the story page.
            showSetup = false
            dismiss()
            onCreate(challenge.id)
        }
    }

    private func createSharedRoom() {
        creating = true
        errorText = nil
        Task {
            defer { creating = false }
            do {
                let challenge = try await store.createSharedRoom(
                    title: title.trimmingCharacters(in: .whitespaces),
                    mode: mode,
                    clipLength: clipLength,
                    orientation: orientation,
                    templateName: selected?.identityKey,
                    momentTitles: resolvedMoments)
                showSetup = false
                dismiss()
                onCreate(challenge.id)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func deleteTemplate(_ template: ChallengeTemplate) {
        let wasSelected = selection.templateID == template.id
        store.deleteCustomTemplate(template)
        if wasSelected {
            selection.clearTemplate(fallingBackTo: ChallengeTemplate.oneDayBuiltins)
        }
    }

    private func beginCustomPromptFlow() {
        showGuided = true
    }

    /// The gear on a poster's corner: adopt that poster, then open the
    /// settings sheet instead of creating anything. This is the whole of the
    /// old second screen, for the person who wants to rename the story, edit
    /// its moments, or invite someone before they start.
    private func openSettings(_ template: ChallengeTemplate) {
        adopt(template)
        errorText = nil
        showSetup = true
    }

    /// Tapping a poster creates the story and leaves for the camera.
    ///
    /// The poster *is* the submit button. Every other control on this screen
    /// had a correct default, so asking for confirmation was asking the user
    /// to re-affirm a choice they had just made — and the previous shape made
    /// it worse than that: `1/2 选拍法` and 下一步 only ever applied to the
    /// poster that happened to be selected by default, so tapping any other
    /// one skipped both. One rule now, and it is the fast one.
    private func createFromPoster(_ template: ChallengeTemplate) {
        guard !creating else { return }
        adopt(template)
        // `adopt` has just synced `title` and `moments` to this poster — or
        // kept a name the user typed in the settings sheet, which is the one
        // case where they told us what to call it. An empty name can't reach
        // `store.create`, so the poster's own name is the floor.
        let typed = title.trimmingCharacters(in: .whitespaces)
        creating = true
        let challenge = store.create(
            title: typed.isEmpty ? template.displayName : typed,
            mode: selection.mode,
            clipLength: clipLength,
            orientation: orientation,
            templateName: template.identityKey,
            momentTitles: resolvedMoments)
        dismiss()
        onCreate(challenge.id)
    }

    /// Makes `template` the story's script, without deciding what happens next.
    private func adopt(_ template: ChallengeTemplate) {
        selection.select(template, oneDay: oneDayTemplates, sevenDay: sevenDayTemplates)
        isCustomPromptStory = false
        syncTitleToTemplate()
    }

    /// What the guided flow wrote, applied to this story — and, if the user
    /// asked for it, kept as a template first.
    ///
    /// Saving takes the ordinary template path from there: the new script is
    /// simply *selected*, exactly as if it had always been on the shelf. That
    /// keeps one code path for "a story made from a template" instead of a
    /// second, subtly different one for scripts written five seconds ago.
    private func applyCustomDraft(_ draft: CustomStoryDraft) {
        title = draft.name
        titleEdited = true
        moments = draft.moments

        if draft.savesToLibrary {
            let saved = store.addCustomTemplate(
                ChallengeTemplate(
                    name: LocalizedText(en: draft.name, zh: draft.name),
                    momentKeys: draft.moments.map {
                        MomentCatalog.key(forDisplay: $0) ?? $0
                    },
                    isCustom: true,
                    presetCoverAssetName: draft.presetCoverAssetName),
                coverImageData: draft.coverImageData)
            isCustomPromptStory = false
            selection.select(
                saved, oneDay: oneDayTemplates, sevenDay: sevenDayTemplates)
        } else {
            isCustomPromptStory = true
            selection.useCustomPrompts()
        }

        // Straight into settings rather than straight into creating: the user
        // just wrote these moments by hand, so this is the one path where the
        // defaults behind a poster haven't been agreed to yet.
        errorText = nil
        showSetup = true
    }

    // MARK: - Derived state

    /// Keeps the story name in step with the chosen script until the user
    /// takes the name over.
    private func syncTitleToTemplate() {
        guard let selected else { return }
        if !titleEdited {
            title = mode == .sevenDay
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
        if selected?.isTimeOnly == true { return nil }
        let cleaned = moments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? selected?.momentKeys : cleaned
    }
}
