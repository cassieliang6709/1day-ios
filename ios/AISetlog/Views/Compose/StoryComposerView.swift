import SwiftUI

/// Making a story: pick a poster, then one page of settings.
///
/// The 1.2 shape was "the poster is the submit button" — a tap created the
/// story with defaults and went straight to filming, and the settings were
/// optional behind a gear on the poster's corner. It was fast, and it was
/// wrong about one thing: 谁一起拍 was in there. The obvious gesture answered
/// it 自己来 without asking, and answering it any other way meant noticing a
/// 26pt icon. That is not a default, it is a decision being made for you.
///
/// So the poster opens the page now, and the page's own button creates the
/// story. Every decision on one page, made once, before anything exists. The
/// page is a sheet rather than a push because the rack behind it is the thing
/// you came from and a sheet keeps it there.
struct StoryComposerView: View {
    var onCreate: (UUID) -> Void = { _ in }
    /// How to leave. Nil means "I was presented, dismiss me" — the sheet path.
    /// `RootShellView` passes a closure instead, because as the 新建 tab this
    /// view has no presentation to dismiss and `dismiss()` is a no-op: without
    /// this the ✕ did nothing and creating a story left the composer on screen
    /// behind the story it had just made.
    var onClose: (() -> Void)? = nil

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
    /// The settings page. Raised by a poster tap — there is no other way to it
    /// and no way past it.
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
                    onChoose: openSettings,
                    onEdit: { editingTemplate = $0 },
                    onDelete: deleteTemplate,
                    coverURL: { store.coverURL(for: $0) })
            }

            // Only for the poster-tap route into a shared room. The settings
            // sheet has its own inline spinner and its own error line above the
            // button; out here on the rack there was neither, so a slow room
            // creation looked like a tap that missed and a failed one looked
            // like nothing at all.
            if creating, !showSetup, withFriends {
                Color.black.opacity(0.18).ignoresSafeArea()
                ProgressView(Strings.creatingRoom)
                    .controlSize(.large)
                    .padding(22)
                    .glassSurface(radius: OneDay.Radius.card)
            }
        }
        .alert(
            Strings.couldNotCreateRoom,
            isPresented: Binding(
                get: { errorText != nil && !showSetup },
                set: { if !$0 { errorText = nil } })
        ) {
            Button(Strings.ok) { errorText = nil }
        } message: {
            Text(errorText ?? "")
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

    /// Just the way out. There is no progress counter and no back chevron
    /// because there is one screen: the settings arrive as a sheet over it, and
    /// a sheet already has its own ✕.
    private var topBar: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: "xmark") { leave() }
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    // MARK: - The settings sheet

    /// The one page: name, 谁一起拍, clip length, frame, and the moment list.
    /// Its button is what creates the story.
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

    /// Leaving, whichever way this view got on screen. See `onClose`.
    private func leave() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

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
            leave()
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
                leave()
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

    /// Tapping a poster: adopt that script, then open the settings page.
    ///
    /// This is the whole flow as of 1.3. It used to create the story on the spot
    /// and the settings were optional, behind a gear — which meant the fast path
    /// answered 谁一起拍 as 自己来 without asking, and answering it any other way
    /// required noticing a 26pt icon in a poster's corner. Now the tap opens the
    /// page and the page's own button is what creates the story, so every
    /// decision is made once, in one place, before anything exists.
    private func openSettings(_ template: ChallengeTemplate) {
        adopt(template)
        errorText = nil
        showSetup = true
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
