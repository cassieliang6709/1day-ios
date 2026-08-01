import SwiftUI

/// Writing your own seven moments, by answering questions instead of staring
/// at a blank list.
///
/// The template carousel is for picking someone else's day. This is for
/// describing your own — and "invent seven moments" is a genuinely hard blank
/// page, so the screen asks seven small questions instead. Each answer is
/// pre-filled with a suggestion, so the fastest path is still one tap, and the
/// questions are shaped so the answers naturally come out in time order.
struct GuidedMomentsView: View {
    /// Called with the finished moment titles, in order.
    let onDone: ([String], String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    @State private var answers: [String] = []
    @State private var storyName: String = ""
    @FocusState private var focused: Int?

    private var questions: [GuidedQuestion] { GuidedQuestion.day }

    private var filledCount: Int {
        answers.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private var canSave: Bool {
        filledCount >= 2 && !storyName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OneDayCanvas(seed: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        heading
                        nameCard
                        ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                            questionCard(index: index, question: question)
                        }
                        footnote
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(Strings.writeYourOwn)
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
            .onAppear {
                guard answers.isEmpty else { return }
                // Pre-filled with the suggestion, so tapping straight through
                // still produces a usable day.
                answers = questions.map { $0.suggestion }
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
                TextField(
                    "", text: $storyName,
                    prompt: Text(Strings.guidedNamePlaceholder))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .tint(Color.oneDayBlue)
            }
        }
    }

    private func questionCard(index: Int, question: GuidedQuestion) -> some View {
        GlassCard(padding: 14, tint: focused == index ? .oneDayBlue : nil) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: question.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.oneDayBlue)
                        .frame(width: 28, height: 28)
                        .background(Color.oneDayBlue.opacity(0.12), in: Circle())

                    Text(question.prompt)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField(
                    "", text: binding(index),
                    prompt: Text(question.suggestion).foregroundStyle(OneDay.inkFaint))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(OneDay.ink)
                    .tint(Color.oneDayBlue)
                    .focused($focused, equals: index)
                    .submitLabel(index == questions.count - 1 ? .done : .next)
                    .onSubmit {
                        focused = index < questions.count - 1 ? index + 1 : nil
                    }
                    .padding(.leading, 37)
            }
        }
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

    /// Blank answers are dropped rather than filmed as empty prompts — leaving
    /// a question unanswered is a way of saying "not that one today".
    private func save() {
        let moments = answers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard moments.count >= 2 else { return }
        onDone(moments, storyName.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

/// One question and the answer it suggests. Ordered through a day so the
/// resulting moments already read as a timeline.
struct GuidedQuestion {
    let prompt: String
    let suggestion: String
    let icon: String

    static var day: [GuidedQuestion] {
        let zh = AppLanguage.effective.resolved == .chinese
        return [
            .init(
                prompt: zh ? "今天是怎么开始的？" : "How does today start?",
                suggestion: zh ? "睁开眼" : "First light",
                icon: "sunrise.fill"),
            .init(
                prompt: zh ? "出门前的最后一件事是什么？" : "The last thing before you head out?",
                suggestion: zh ? "出门前" : "Out the door",
                icon: "door.left.hand.open"),
            .init(
                prompt: zh ? "上午你会在哪里？" : "Where will you be this morning?",
                suggestion: zh ? "上午的位置" : "Where I land",
                icon: "mappin.circle.fill"),
            .init(
                prompt: zh ? "今天吃了什么？" : "What did you eat?",
                suggestion: zh ? "今天这一餐" : "Today's plate",
                icon: "fork.knife"),
            .init(
                prompt: zh ? "下午最想记住的一件小事？" : "One small thing worth keeping this afternoon?",
                suggestion: zh ? "小小的好事" : "A small good thing",
                icon: "sparkles"),
            .init(
                prompt: zh ? "傍晚的光是什么样子？" : "What does the evening light look like?",
                suggestion: zh ? "傍晚的光" : "Evening light",
                icon: "sun.horizon.fill"),
            .init(
                prompt: zh ? "今天是怎么结束的？" : "How does today end?",
                suggestion: zh ? "睡前" : "Before sleep",
                icon: "moon.stars.fill"),
        ]
    }
}
