import SwiftUI

/// What the guided flow hands back: a story to start now, and — if the user
/// wants it — a template to keep.
struct CustomStoryDraft {
    var moments: [String]
    var name: String
    /// Whether this also becomes a reusable template rather than evaporating
    /// once the story is made.
    var savesToLibrary: Bool
    /// Bytes of a cover picked from the photo library. Nil means the app
    /// matches one from the prompts.
    var coverImageData: Data?
    /// A bundled scene chosen from the preset cover library.
    var presetCoverAssetName: String?
}

/// A small blank canvas for a user's own prompts. It starts with two rows so
/// the user does not have to predict an entire day before anything happens.
struct GuidedMomentsView: View {
    let onDone: (CustomStoryDraft) -> Void
    /// Injectable so previews and tests don't reach the network.
    var suggestions: any PromptSuggesting = RemotePromptSuggestionService()

    @Environment(\.dismiss) private var dismiss
    @Environment(PromptSuggestionMetrics.self) private var metrics
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    @State private var answers = ["", ""]
    @State private var storyName = ""
    @State private var showPromptLibrary = false
    @FocusState private var focused: Int?

    /// On by default. Writing seven prompts is the expensive part; throwing
    /// them away after one story is the surprising outcome, not keeping them.
    @State private var savesToLibrary = true
    @State private var coverChoice: TemplateCoverChoice = .unchanged

    /// The sentence about today, and what came back from it.
    @State private var intent = ""
    @State private var isSuggesting = false
    @State private var suggestionNote: String?
    /// Kept so the rewrite rate has something to compare against at save time.
    @State private var offeredPrompts: [String] = []

    /// A full day's worth. The whole point is not having to invent them one at
    /// a time, and every row is editable afterwards.
    private static let suggestionCount = 7

    private var filledCount: Int {
        answers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var needsName: Bool {
        storyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        filledCount >= 2 && !needsName
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heading
                        intentCard
                        nameCard
                        promptEditor
                        libraryButton
                        keepItCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            // The decision this screen exists for gets the one primary button,
            // pinned where the composer keeps its own — it used to be a small
            // word in the nav bar losing to a full-width 出题目 mid-page.
            .safeAreaInset(edge: .bottom) { saveFooter }
            .navigationTitle(Strings.customPromptsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
            }
            // The intent field is the first thing on screen, so this is about
            // as early as a warm-up can go without doing it for people who
            // never open the composer.
            .task { await suggestions.warmUp() }
            .sheet(isPresented: $showPromptLibrary) {
                PromptLibraryPicker(onChoose: addFromLibrary)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var saveFooter: some View {
        Button(action: save) {
            Text(filledCount > 0
                ? Strings.useTheseMomentsCount(filledCount)
                : Strings.useTheseMoments)
        }
        .buttonStyle(.primaryAction)
        .disabled(!canSave)
        .accessibilityIdentifier("use-these-moments")
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Strings.guidedHeading)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
        }
        .padding(.top, 8)
    }

    private var nameCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.storyNameLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.inkFaint)
                TextField("", text: $storyName, prompt: Text(Strings.guidedNamePlaceholder))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .tint(Color.oneDayBrand)
                    .accessibilityIdentifier("custom-story-name")

                // Only once there are prompts to save: before that the empty
                // field is obviously unfinished and doesn't need telling on.
                if needsName, filledCount >= 2 {
                    Text(Strings.storyNameNeeded)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.oneDayBrand)
                        .padding(.top, 3)
                        .transition(.opacity)
                }
            }
        }
        .animation(OneDay.Motion.soft, value: canSave)
    }

    /// A day that hasn't happened yet is hard to write prompts for, which is
    /// where the blank list loses people. But "今天要搬家" is sayable now.
    private var intentCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                // No sparkles on the heading: the glyph marks the one thing
                // that calls the AI, and that's the button below.
                Text(Strings.intentHeading)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)

                TextField("", text: $intent, prompt: Text(Strings.intentPlaceholder))
                    .font(.system(size: 15.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .tint(Color.oneDayBrand)
                    .submitLabel(.go)
                    .onSubmit(generatePrompts)
                    .disabled(isSuggesting)
                    .accessibilityIdentifier("today-intent")
                    // A note about the last sentence is wrong about this one.
                    .onChange(of: intent) { _, _ in suggestionNote = nil }

                // Secondary on purpose: generating is a helper, saving is the
                // decision. Two primaries on one screen read as two exits.
                Button(action: generatePrompts) {
                    HStack(spacing: 7) {
                        if isSuggesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(generateLabel)
                    }
                }
                .buttonStyle(.softAction)
                .disabled(isSuggesting || trimmedIntent.isEmpty)
                // The soft style doesn't dim itself when disabled.
                .opacity(trimmedIntent.isEmpty ? 0.55 : 1)
                .accessibilityIdentifier("suggest-prompts")

                if let suggestionNote {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(OneDay.inkSoft)
                            .accessibilityHidden(true)
                        Text(suggestionNote)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button(Strings.retry, action: generatePrompts)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.oneDayBrand)
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                            .disabled(isSuggesting || trimmedIntent.isEmpty)
                            .accessibilityIdentifier("suggest-retry")
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(OneDay.Motion.soft, value: suggestionNote)
    }

    /// 换一批 once the list still shows the last round untouched: the same
    /// tap now swaps those rows instead of looking for blanks that aren't there.
    private var generateLabel: String {
        if isSuggesting { return Strings.suggestingPrompts }
        return SuggestedPromptFill.canReplace(answers, offered: offeredPrompts)
            ? Strings.suggestAnotherSet
            : Strings.suggestPrompts
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: Strings.yourPrompts)

            GlassCard(padding: 12) {
                VStack(spacing: 0) {
                    ForEach(answers.indices, id: \.self) { index in
                        promptRow(index)
                        if index < answers.count - 1 {
                            Divider().overlay(OneDay.hairline).padding(.leading, 38)
                        }
                    }

                    if answers.count < StoryMoments.maxCount {
                        Divider().overlay(OneDay.hairline).padding(.leading, 38)
                        Button(action: addBlankPrompt) {
                            Label(Strings.addAnotherPrompt, systemImage: "plus.circle.fill")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.oneDayBrand)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func promptRow(_ index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.oneDayBrand, in: Circle())

            TextField(
                "",
                text: binding(index),
                prompt: Text(Strings.customPromptPlaceholder(index + 1)))
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .tint(Color.oneDayBrand)
                .focused($focused, equals: index)
                .submitLabel(index == answers.count - 1 ? .done : .next)
                .onSubmit {
                    focused = index < answers.count - 1 ? index + 1 : nil
                }
                .accessibilityIdentifier("custom-prompt-\(index + 1)")

            if answers.count > 2 {
                Button {
                    guard answers.indices.contains(index) else { return }
                    answers.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(OneDay.inkFaint)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.deleteMoment)
            }
        }
        .padding(.vertical, 9)
    }

    private var libraryButton: some View {
        Button {
            showPromptLibrary = true
        } label: {
            Label(Strings.chooseFromPromptLibrary, systemImage: "rectangle.stack.badge.plus")
        }
        .buttonStyle(.softAction)
    }

    /// Keeping the prompts is a decision about the future, so it sits at the
    /// end — after the list it's talking about exists and is worth keeping.
    private var keepItCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $savesToLibrary) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Strings.saveToTemplateLibrary)
                            .font(.system(size: 15.5, weight: .bold, design: .rounded))
                            .foregroundStyle(OneDay.ink)
                        Text(Strings.saveToTemplateLibraryNote)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(OneDay.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Color.oneDayBrand)
                .accessibilityIdentifier("save-to-template-library")

                if savesToLibrary {
                    Divider().overlay(OneDay.hairline)
                    SectionLabel(text: Strings.templateCoverLabel)
                    TemplateCoverField(
                        matchedAssetName: matchedCoverAssetName,
                        choice: $coverChoice)
                }
            }
        }
        .animation(OneDay.Motion.soft, value: savesToLibrary)
    }

    /// What the cover would be if the user leaves it alone — recomputed as
    /// they type, so the preview is honest about what they'd get.
    private var matchedCoverAssetName: String {
        TemplateCoverMatcher.assetName(forMomentKeys: filledAnswers, name: storyName)
            ?? TemplateCoverMatcher.fallbackAssetName
    }

    private var filledAnswers: [String] {
        answers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }


    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { answers.indices.contains(index) ? answers[index] : "" },
            set: { if answers.indices.contains(index) { answers[index] = $0 } })
    }

    private func addBlankPrompt() {
        guard answers.count < StoryMoments.maxCount else { return }
        answers.append("")
        focused = answers.count - 1
    }

    private func addFromLibrary(_ prompt: String) {
        if let emptyIndex = answers.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            answers[emptyIndex] = prompt
        } else if answers.count < StoryMoments.maxCount {
            answers.append(prompt)
        }
    }

    private var trimmedIntent: String {
        intent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Failure is quiet on purpose. The list underneath is still there and
    /// still works, so there's nothing to interrupt anyone about — one line
    /// saying why nothing appeared, and no alert.
    private func generatePrompts() {
        let sentence = trimmedIntent
        guard !sentence.isEmpty, !isSuggesting else { return }

        focused = nil
        isSuggesting = true
        suggestionNote = nil

        Task {
            defer { isSuggesting = false }
            do {
                let suggestion = try await suggestions.suggestStory(
                    intent: sentence,
                    count: Self.suggestionCount,
                    language: appLanguage)
                metrics.recordGenerated()
                // Rows still reading as the previous round are swapped, so a
                // second tap on a full list gives a new set instead of nothing.
                answers = SuggestedPromptFill.apply(
                    suggestion.prompts, to: answers, replacing: offeredPrompts)
                offeredPrompts = suggestion.prompts
                // Read the current fields after the await: edits made while
                // generating win as well. Old servers still seed from intent.
                if needsName, let seeded = suggestion.title ?? IntentStoryName.derive(from: sentence) {
                    storyName = seeded
                }
            } catch PromptSuggestionError.rateLimited {
                suggestionNote = Strings.suggestRateLimited
            } catch {
                suggestionNote = Strings.suggestFailed
            }
            // Quiet on screen, but not silent: VoiceOver users otherwise hear
            // the spinner stop and nothing else.
            if let suggestionNote {
                AccessibilityNotification.Announcement(suggestionNote).post()
            }
        }
    }

    private func save() {
        let moments = filledAnswers
        guard moments.count >= 2 else { return }
        // Which of the generated prompts survived contact with a person. This
        // is the number the whole feature exists to produce.
        metrics.recordAdopted(offered: offeredPrompts, saved: moments)
        onDone(CustomStoryDraft(
            moments: moments,
            name: storyName.trimmingCharacters(in: .whitespacesAndNewlines),
            savesToLibrary: savesToLibrary,
            coverImageData: coverChoice.pickedData,
            presetCoverAssetName: coverChoice.resolvedPreset(existing: nil)))
        dismiss()
    }
}

private struct PromptLibraryPicker: View {
    let onChoose: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 3)

                ScrollView {
                    FlowLayout(spacing: 9) {
                        ForEach(ChallengeTemplate.promptPool, id: \.self) { prompt in
                            Button {
                                onChoose(MomentCatalog.localize(prompt))
                                dismiss()
                            } label: {
                                Label(
                                    MomentCatalog.localize(prompt),
                                    systemImage: MomentCatalog.icon(for: prompt))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(OneDay.ink)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 10)
                                    .background(OneDay.surface.opacity(0.94), in: Capsule())
                                    .overlay(Capsule().strokeBorder(OneDay.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(Strings.promptLibrary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
            }
        }
    }
}
