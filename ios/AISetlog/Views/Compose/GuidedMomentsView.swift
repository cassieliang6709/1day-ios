import SwiftUI

/// A small blank canvas for a user's own prompts. It starts with two rows so
/// the user does not have to predict an entire day before anything happens.
struct GuidedMomentsView: View {
    let onDone: ([String], String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    @State private var answers = ["", ""]
    @State private var storyName = ""
    @State private var showPromptLibrary = false
    @FocusState private var focused: Int?

    private var filledCount: Int {
        answers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var canSave: Bool {
        filledCount >= 2 && !storyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heading
                        nameCard
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
            Text(Strings.guidedFootnote(filled: filledCount))
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

    private func save() {
        let moments = answers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard moments.count >= 2 else { return }
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
