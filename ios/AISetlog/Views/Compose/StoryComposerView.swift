import SwiftUI

/// Screens 2 and 3 — choosing a story, then setting it up.
///
/// The old creation screen was one long form: a title field, a fanned deck,
/// five settings rows and a toggle, all competing. Splitting it means step one
/// can be nothing but posters (choosing a mood should feel like browsing a
/// shelf) and step two can be short enough to read in a glance.
struct StoryComposerView: View {
    var onCreate: (UUID) -> Void = { _ in }

    @Environment(ChallengeStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    enum Step: Int { case mood, setup }

    @State private var step: Step = .mood
    @State private var selectedTemplateID: UUID? = ChallengeTemplate.liveWithMe.id
    @State private var mode: Challenge.Mode = .oneDay
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
    @State private var momentsEdited = false
    @State private var isCustomPromptStory = false
    @State private var showGuided = false
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

    private var selected: ChallengeTemplate? {
        guard let selectedTemplateID else { return nil }
        return allTemplates.first { $0.id == selectedTemplateID }
    }

    var body: some View {
        ZStack {
            OneDayCanvas(seed: 1)

            VStack(spacing: 0) {
                topBar

                switch step {
                case .mood:
                    MoodStep(
                        oneDayTemplates: oneDayTemplates,
                        sevenDayTemplates: sevenDayTemplates,
                        selectedTemplateID: $selectedTemplateID,
                        mode: $mode,
                        onBuildOwn: beginCustomPromptFlow,
                        onEdit: { editingTemplate = $0 },
                        onDelete: deleteTemplate)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))

                case .setup:
                    SetupStep(
                        template: selected,
                        title: $title,
                        titleEdited: $titleEdited,
                        withFriends: $withFriends,
                        clipLength: $clipLength,
                        orientation: $orientation,
                        moments: $moments,
                        isOneDay: mode == .oneDay,
                        isTimeOnly: selected?.isTimeOnly == true,
                        memberNames: knownFriendNames,
                        errorText: errorText)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }

                footer
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInView { createSharedRoom() }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showGuided) {
            GuidedMomentsView { written, name in
                mode = .oneDay
                isCustomPromptStory = true
                selectedTemplateID = nil
                moments = written
                momentsEdited = true
                title = name
                titleEdited = true
                withAnimation(OneDay.Motion.soft) { step = .setup }
            }
        }
        .sheet(item: $editingTemplate) { template in
            BuildTemplateView(template: template) { updated in
                store.updateCustomTemplate(updated)
            }
        }
        .onAppear(perform: syncTitleToTemplate)
        .onChange(of: selectedTemplateID) { _, newID in
            guard newID != nil else { return }
            isCustomPromptStory = false
            titleEdited = false
            momentsEdited = false
            syncTitleToTemplate()
        }
        .onChange(of: mode) { _, newMode in
            guard !isCustomPromptStory else { return }
            let validTemplates = newMode == .oneDay ? oneDayTemplates : sevenDayTemplates
            guard !validTemplates.contains(where: { $0.id == selectedTemplateID }) else { return }
            selectedTemplateID = validTemplates.first?.id
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            IconBubble(systemName: step == .mood ? "xmark" : "chevron.left") {
                if step == .mood {
                    dismiss()
                } else {
                    withAnimation(OneDay.Motion.soft) { step = .mood }
                }
            }

            Spacer()

            StepDots(count: 2, index: step.rawValue)

            Spacer()

            // Balances the leading bubble so the dots stay centred.
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: advance) {
                HStack(spacing: 8) {
                    if creating {
                        ProgressView().tint(.white)
                    } else {
                        Text(primaryTitle)
                        Image(systemName: step == .mood ? "arrow.right" : "sparkles")
                    }
                }
            }
            .buttonStyle(.primaryAction)
            .disabled(!canAdvance)
            .opacity(canAdvance ? 1 : 0.55)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var primaryTitle: String {
        switch step {
        case .mood: return Strings.next
        case .setup: return withFriends ? Strings.createRoom : Strings.createStoryCTA
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .mood: return selected != nil || isCustomPromptStory
        case .setup: return !title.trimmingCharacters(in: .whitespaces).isEmpty && !creating
        }
    }

    // MARK: - Actions

    private func advance() {
        switch step {
        case .mood:
            withAnimation(OneDay.Motion.soft) { step = .setup }
        case .setup:
            start()
        }
    }

    private func start() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if withFriends {
            if account.isSignedIn { createSharedRoom() } else { showSignIn = true }
        } else {
            let challenge = store.create(
                title: name,
                mode: mode,
                clipLength: clipLength,
                orientation: orientation,
                templateName: selected?.identityKey,
                momentTitles: resolvedMoments)
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
                dismiss()
                onCreate(challenge.id)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func deleteTemplate(_ template: ChallengeTemplate) {
        let wasSelected = selectedTemplateID == template.id
        store.deleteCustomTemplate(template)
        if wasSelected {
            selectedTemplateID = ChallengeTemplate.oneDayBuiltins
                .first(where: { !$0.isTimeOnly })?.id
        }
    }

    private func beginCustomPromptFlow() {
        showGuided = true
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
        if !momentsEdited {
            moments = selected.momentKeys ?? []
        }
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

    /// Names already seen in the user's rooms — shown as suggestions on the
    /// "with friends" card so it isn't an empty promise.
    private var knownFriendNames: [String] {
        var seen: [String] = []
        for challenge in store.challenges where challenge.isShared {
            for member in store.members(for: challenge.id) where !seen.contains(member.name) {
                seen.append(member.name)
            }
        }
        return seen
    }
}

/// Two-step progress, as dots rather than a bar — the flow is short enough
/// that a bar would overstate it.
struct StepDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { dot in
                Capsule()
                    .fill(dot <= index ? Color.oneDayBlue : Color.oneDaySky.opacity(0.3))
                    .frame(width: dot == index ? 22 : 7, height: 7)
            }
        }
        .animation(OneDay.Motion.snap, value: index)
    }
}
