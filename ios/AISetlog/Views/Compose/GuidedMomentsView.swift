import SwiftUI

/// A small blank canvas for a user's own prompts. It starts with two rows so
/// the user does not have to predict an entire day before anything happens.
struct GuidedMomentsView: View {
    let onDone: ([String], String) -> Void
    /// Injectable so previews and tests don't reach the network.
    var suggestions: any PromptSuggesting = RemotePromptSuggestionService()

    @Environment(\.dismiss) private var dismiss
    @Environment(PromptSuggestionMetrics.self) private var metrics
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    @State private var answers = ["", ""]
    @State private var storyName = ""
    @State private var showPromptLibrary = false
    @FocusState private var focused: Int?

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
                        nameCard
                        intentCard
                        promptEditor
                        libraryButton
                        footnote
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(Strings.customPromptsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.useTheseMoments, action: save)
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showPromptLibrary) {
                PromptLibraryPicker(onChoose: addFromLibrary)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Strings.guidedHeading)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(OneDay.ink)
            Text(Strings.guidedSubtitle)
                .font(.system(size: 14.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
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
                    .tint(Color.oneDayBlue)
                    .accessibilityIdentifier("custom-story-name")

                // Only once there are prompts to save: before that the empty
                // field is obviously unfinished and doesn't need telling on.
                if needsName, filledCount >= 2 {
                    Text(Strings.storyNameNeeded)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.oneDayBlue)
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
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.oneDayBlue)
                    Text(Strings.intentHeading)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                }

                Text(Strings.intentSubtitle)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("", text: $intent, prompt: Text(Strings.intentPlaceholder))
                    .font(.system(size: 15.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .tint(Color.oneDayBlue)
                    .submitLabel(.go)
                    .onSubmit(generatePrompts)
                    .disabled(isSuggesting)
                    .accessibilityIdentifier("today-intent")

                Button(action: generatePrompts) {
                    HStack(spacing: 7) {
                        if isSuggesting {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(isSuggesting ? Strings.suggestingPrompts : Strings.suggestPrompts)
                    }
                }
                .buttonStyle(.primaryAction)
                .disabled(isSuggesting || trimmedIntent.isEmpty)
                .accessibilityIdentifier("suggest-prompts")

                if let suggestionNote {
                    Text(suggestionNote)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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

                    if answers.count < 7 {
                        Divider().overlay(OneDay.hairline).padding(.leading, 38)
                        Button(action: addBlankPrompt) {
                            Label(Strings.addAnotherPrompt, systemImage: "plus.circle.fill")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.oneDayBlue)
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
                .background(Color.oneDayBlue, in: Circle())

            TextField(
                "",
                text: binding(index),
                prompt: Text(Strings.customPromptPlaceholder(index + 1)))
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .tint(Color.oneDayBlue)
                .focused($focused, equals: index)
                .submitLabel(index == answers.count - 1 ? .done : .next)
                .onSubmit {
                    focused = index < answers.count - 1 ? index + 1 : nil
                }
                .accessibilityIdentifier("custom-prompt-\(index + 1)")

            if answers.count > 2 {
                Button {
                    answers.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(OneDay.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.delete)
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

    private var footnote: some View {
        HStack(alignment: .top, spacing: 10) {
            OneDayBuddy(size: 30)
            Text(Strings.guidedFootnote(filled: filledCount, needsName: needsName))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { answers.indices.contains(index) ? answers[index] : "" },
            set: { if answers.indices.contains(index) { answers[index] = $0 } })
    }

    private func addBlankPrompt() {
        guard answers.count < 7 else { return }
        answers.append("")
        focused = answers.count - 1
    }

    private func addFromLibrary(_ prompt: String) {
        if let emptyIndex = answers.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            answers[emptyIndex] = prompt
        } else if answers.count < 7 {
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
                let prompts = try await suggestions.suggest(
                    intent: sentence,
                    count: Self.suggestionCount,
                    language: appLanguage)
                metrics.recordGenerated()
                offeredPrompts = prompts
                answers = SuggestedPromptFill.apply(prompts, to: answers)
                // The sentence already named the day. Only when the field is
                // still blank — a name someone typed is never overwritten.
                if needsName, let seeded = IntentStoryName.derive(from: sentence) {
                    storyName = seeded
                }
            } catch PromptSuggestionError.rateLimited {
                suggestionNote = Strings.suggestRateLimited
            } catch {
                suggestionNote = Strings.suggestFailed
            }
        }
    }

    private func save() {
        let moments = answers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard moments.count >= 2 else { return }
        // Which of the generated prompts survived contact with a person. This
        // is the number the whole feature exists to produce.
        metrics.recordAdopted(offered: offeredPrompts, saved: moments)
        onDone(moments, storyName.trimmingCharacters(in: .whitespacesAndNewlines))
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
