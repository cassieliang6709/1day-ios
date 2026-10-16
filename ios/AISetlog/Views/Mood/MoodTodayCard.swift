import SwiftUI

/// 我的 → 今天的心情. One tap on a face records today's mood; the optional
/// one-line note appears once a mood is picked. Both can be changed all day.
/// Private: nothing here goes to rooms or friends.
struct MoodTodayCard: View {
    @Environment(MoodStore.self) private var moods

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: Strings.moodSectionTitle)
                .padding(.horizontal, 20)
            GlassCard {
                MoodCardContent(today: moods.today, onPick: { moods.setMood($0) },
                                onNote: { moods.setNote($0) })
            }
            .padding(.horizontal, 20)
        }
        .accessibilityIdentifier("mood-today-card")
    }
}

private struct MoodCardContent: View {
    let today: MoodEntry?
    let onPick: (Mood) -> Void
    let onNote: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.moodPrompt)
                .font(OneDay.Font.callout)
                .foregroundStyle(OneDay.ink)
            MoodFaceRow(selected: today?.mood, onPick: onPick)
            if let today {
                MoodNoteField(entry: today, onCommit: onNote)
            }
            Label(Strings.moodPrivateHint, systemImage: "lock.fill")
                .font(OneDay.Font.micro)
                .foregroundStyle(OneDay.inkFaint)
        }
    }
}

private struct MoodFaceRow: View {
    let selected: Mood?
    let onPick: (Mood) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Mood.allCases) { mood in
                MoodFaceButton(mood: mood, state: state(for: mood)) { onPick(mood) }
            }
        }
    }

    private func state(for mood: Mood) -> MoodFaceButton.State {
        guard let selected else { return .idle }
        return selected == mood ? .selected : .dimmed
    }
}

struct MoodFaceButton: View {
    enum State { case idle, selected, dimmed }

    let mood: Mood
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                face
                Text(mood.label)
                    .font(OneDay.Font.micro)
                    .foregroundStyle(state == .selected ? OneDay.brandText : OneDay.inkSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(state == .dimmed ? 0.45 : 1)
        .animation(.spring(duration: 0.25), value: state)
        .accessibilityLabel(mood.label)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
        .accessibilityIdentifier("mood-\(mood.rawValue)")
    }

    private var face: some View {
        Image(mood.imageName)
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 50)
            .padding(4)
            .background(Circle().fill(Color.oneDayBrand.opacity(state == .selected ? 0.18 : 0)))
            .scaleEffect(state == .selected ? 1.08 : 1)
    }
}

private struct MoodNoteField: View {
    let entry: MoodEntry
    let onCommit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(Strings.moodNotePlaceholder, text: $text)
            .font(OneDay.Font.subhead)
            .foregroundStyle(OneDay.ink)
            .submitLabel(.done)
            .focused($focused)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(OneDay.surfaceSoft, in: RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous))
            .onAppear { text = entry.note }
            .onChange(of: entry.day) { _, _ in text = entry.note }
            .onChange(of: focused) { _, isFocused in if !isFocused { onCommit(text) } }
            .onSubmit { onCommit(text) }
            .onDisappear { onCommit(text) }
            .accessibilityIdentifier("mood-note")
    }
}
