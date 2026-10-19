import SwiftUI

/// What 写今天的清单 hands back to the composer.
struct CustomStoryDraft {
    var moments: [String]
    /// A name the AI offered, or one derived from the sentence about today.
    /// The composer only uses it while the user hasn't typed a name.
    var suggestedName: String?
}

/// 写今天的清单 (1.5): the one editor behind the composer's list. A single
/// line about today with a small 帮我写 that asks the AI to fill the list,
/// then the list itself — typed, reordered, trimmed — and one button at the
/// bottom. 自己写 and AI 帮我写 used to be two entries into this page.
struct GuidedMomentsView: View {
    /// What the list holds now: the last edit. (Templates, and 从模板开始 /
    /// 存为我的模板 with them, are gone — 1.5.)
    var initialMoments: [String] = []
    let onDone: (CustomStoryDraft) -> Void
    /// Injectable so previews and tests don't reach the network.
    var suggestions: any PromptSuggesting = RemotePromptSuggestionService()

    @Environment(\.dismiss) private var dismiss
    @Environment(PromptSuggestionMetrics.self) private var metrics
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    @State private var rows: [ListRow] = []
    @State private var showPromptLibrary = false
    @FocusState private var focused: UUID?

    @State private var intent = ""
    @State private var isSuggesting = false
    @State private var suggestionNote: String?
    @State private var suggestedName: String?
    /// Kept so the rewrite rate has something to compare against at save time.
    @State private var offeredPrompts: [String] = []

    /// A full day's worth; every row stays editable afterwards.
    private static let suggestionCount = 7

    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 1)
                list
            }
            .safeAreaInset(edge: .bottom) { saveFooter }
            .navigationTitle(Strings.composerWriteList)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                }
            }
            .task { await suggestions.warmUp() }
            .onAppear(perform: seed)
            .sheet(isPresented: $showPromptLibrary) {
                PromptLibraryPicker(onChoose: addFromLibrary)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Layout

    private var list: some View {
        List {
            Section { intentRow } footer: { noteFooter }
            Section { listRows; addRow } header: { SectionLabel(text: Strings.listSection) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .listSectionSpacing(16)
        .contentMargins(.horizontal, ComposerLayout.margin, for: .scrollContent)
        // Always reorderable: the handles are the only edit-mode chrome,
        // because every row opts out of swipe-to-delete below.
        .environment(\.editMode, .constant(.active))
    }

    private var intentRow: some View {
        HStack(spacing: 10) {
            TextField("", text: $intent, prompt: Text(Strings.listIntentPlaceholder))
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .tint(Color.oneDayBrand)
                .submitLabel(.go)
                .onSubmit(generatePrompts)
                .disabled(isSuggesting)
                .accessibilityIdentifier("today-intent")
                .onChange(of: intent) { _, _ in suggestionNote = nil }
            helpButton
        }
        .listRowBackground(OneDay.surface)
    }

    private var helpButton: some View {
        Button(action: generatePrompts) {
            HStack(spacing: 5) {
                if isSuggesting {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(helpLabel)
            }
        }
        .buttonStyle(PillButtonStyle(filled: true))
        .disabled(isSuggesting || trimmedIntent.isEmpty)
        .accessibilityIdentifier("suggest-prompts")
    }

    @ViewBuilder private var noteFooter: some View {
        if let suggestionNote {
            HStack(spacing: 8) {
                Text(suggestionNote)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.inkSoft)
                Button(Strings.retry, action: generatePrompts)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.brandText)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("suggest-retry")
            }
        }
    }

    private var listRows: some View {
        ForEach($rows) { $row in
            ListRowView(
                number: number(of: row.id),
                text: $row.text,
                placeholder: Strings.customPromptPlaceholder(number(of: row.id)),
                isLast: row.id == rows.last?.id,
                canRemove: rows.count > 2,
                focused: $focused,
                rowID: row.id,
                onSubmit: { focusNext(after: row.id) },
                onRemove: { remove(row.id) })
                .deleteDisabled(true)
                .listRowBackground(OneDay.surface)
        }
        .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            if rows.count < StoryMoments.maxCount {
                Button(action: addBlankRow) {
                    PillLabel(text: Strings.listAddRow, systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle(filled: false))
                .accessibilityIdentifier("list-add-row")
            }
            Button { showPromptLibrary = true } label: {
                PillLabel(text: Strings.listFromIdeas, systemImage: "lightbulb")
            }
            .buttonStyle(PillButtonStyle(filled: false))
            Spacer(minLength: 0)
        }
        .moveDisabled(true)
        .listRowBackground(OneDay.surface)
    }

    private var saveFooter: some View {
        Button(action: save) {
            Text(filledCount >= 2 ? Strings.listUseCount(filledCount) : Strings.listUse)
        }
        .buttonStyle(.primaryAction)
        .disabled(!canSave)
        .accessibilityIdentifier("use-these-moments")
        .padding(.horizontal, ComposerLayout.margin)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - State

    private var filledAnswers: [String] {
        rows.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var filledCount: Int { filledAnswers.count }
    private var canSave: Bool { filledCount >= 2 }

    private var trimmedIntent: String {
        intent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 换一批 once the list still shows the last round untouched.
    private var helpLabel: String {
        if isSuggesting { return Strings.listHelpWorking }
        return SuggestedPromptFill.canReplace(rows.map(\.text), offered: offeredPrompts)
            ? Strings.listHelpAgain
            : Strings.listHelpWrite
    }

    private func number(of id: UUID) -> Int {
        (rows.firstIndex { $0.id == id } ?? 0) + 1
    }

    private func seed() {
        guard rows.isEmpty else { return }
        var texts = initialMoments.map { MomentCatalog.localize($0) }
        while texts.count < 2 { texts.append("") }
        rows = texts.map { ListRow(text: $0) }
    }

    private func focusNext(after id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        focused = index < rows.count - 1 ? rows[index + 1].id : nil
    }

    private func remove(_ id: UUID) {
        guard rows.count > 2 else { return }
        withAnimation(OneDay.Motion.soft) { rows.removeAll { $0.id == id } }
    }

    private func addBlankRow() {
        guard rows.count < StoryMoments.maxCount else { return }
        let row = ListRow(text: "")
        rows.append(row)
        DispatchQueue.main.async { focused = row.id }
    }

    private func addFromLibrary(_ prompt: String) {
        if let empty = rows.firstIndex(where: {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            rows[empty].text = prompt
        } else if rows.count < StoryMoments.maxCount {
            rows.append(ListRow(text: prompt))
        }
    }

    /// Rewrites the texts in place, keeping each surviving row's identity so
    /// focus and reordering don't jump.
    private func setTexts(_ texts: [String]) {
        rows = texts.enumerated().map { index, text in
            ListRow(id: index < rows.count ? rows[index].id : UUID(), text: text)
        }
    }

    /// Failure is quiet on purpose: the list still works, so one line under
    /// the field says why nothing appeared, and no alert.
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
                    intent: sentence, count: Self.suggestionCount, language: appLanguage)
                metrics.recordGenerated()
                setTexts(SuggestedPromptFill.apply(
                    suggestion.prompts, to: rows.map(\.text), replacing: offeredPrompts))
                offeredPrompts = suggestion.prompts
                suggestedName = suggestion.title ?? IntentStoryName.derive(from: sentence)
            } catch PromptSuggestionError.rateLimited {
                suggestionNote = Strings.suggestRateLimited
            } catch {
                suggestionNote = Strings.suggestFailed
            }
            if let suggestionNote {
                AccessibilityNotification.Announcement(suggestionNote).post()
            }
        }
    }

    private func save() {
        let moments = filledAnswers
        guard moments.count >= 2 else { return }
        metrics.recordAdopted(offered: offeredPrompts, saved: moments)
        onDone(CustomStoryDraft(
            moments: moments,
            suggestedName: suggestedName))
        dismiss()
    }
}

private struct ListRow: Identifiable {
    var id = UUID()
    var text: String
}

/// One line of the checklist: its number, the text, a small remove button.
/// The reorder handle is the List's own, drawn after it.
private struct ListRowView: View {
    let number: Int
    @Binding var text: String
    let placeholder: String
    let isLast: Bool
    let canRemove: Bool
    var focused: FocusState<UUID?>.Binding
    let rowID: UUID
    let onSubmit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(OneDay.inkFaint)
                .frame(width: 18, alignment: .trailing)
            TextField("", text: $text, prompt: Text(placeholder))
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundStyle(OneDay.ink)
                .tint(Color.oneDayBrand)
                .focused(focused, equals: rowID)
                .submitLabel(isLast ? .done : .next)
                .onSubmit(onSubmit)
                .accessibilityIdentifier("custom-prompt-\(number)")
            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(OneDay.inkFaint)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Strings.deleteMoment)
            }
        }
        .frame(minHeight: 32)
    }
}

/// Icon and words side by side. Not `Label`: inside a List row in edit mode
/// a `Label` drops to its icon alone.
private struct PillLabel: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(text)
        }
    }
}

/// A small capsule for helpers (帮我写, 加一项) — never the screen's main
/// action, which stays the one `.primaryAction` at the bottom.
private struct PillButtonStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, filled: filled)
    }

    private struct Pill: View {
        let configuration: Configuration
        let filled: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(OneDay.brandText)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.oneDayBrand.opacity(filled ? 0.14 : 0), in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : OneDay.hairline, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(OneDay.Motion.snap, value: configuration.isPressed)
                .fixedSize()
        }
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
                        ForEach(MomentCatalog.suggestionPool, id: \.self) { prompt in
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
