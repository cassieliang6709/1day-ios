import SwiftUI

/// 我的 → 今天的心情. Pick a face, optionally write (or say) one line, tap
/// 记下了. After that the card shows the saved day — big face, the note — with
/// a small 改 to edit and a way to chat with the mascot about it.
/// Private: nothing here goes to rooms or friends.
struct MoodTodayCard: View {
    @Environment(MoodStore.self) private var moods
    @State private var isEditing = false
    @State private var showChat = false
    /// Bumped when the date rolls over or the app comes back, so a card left
    /// on screen overnight shows today (empty) rather than yesterday's mood.
    @State private var dayTick = 0
    @Environment(\.scenePhase) private var scenePhase
    /// Read so a renamed mascot renames the chat button straight away.
    @AppStorage(MascotName.storageKey) private var mascotName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: Strings.moodSectionTitle)
                .padding(.horizontal, 20)
            GlassCard { content }
                .padding(.horizontal, 20)
        }
        .animation(OneDay.Motion.soft, value: phase)
        .sheet(isPresented: $showChat) { MascotChatSheet() }
        .accessibilityIdentifier("mood-today-card")
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in newDay() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { newDay() } }
    }

    private var phase: MoodCardPhase {
        _ = dayTick
        _ = mascotName
        return MoodCardPhase(entry: moods.today, isEditing: isEditing)
    }

    private func newDay() {
        dayTick += 1
        if moods.today == nil { isEditing = false }
    }

    @ViewBuilder private var content: some View {
        if phase == .saved, let today = moods.today {
            MoodSavedContent(entry: today, onEdit: { isEditing = true }, onChat: { showChat = true })
        } else {
            MoodEditorContent(today: moods.today, onPick: pick,
                              onNote: { moods.setNote($0) }, onDone: { isEditing = false })
        }
    }

    private func pick(_ mood: Mood) {
        // The first pick of the day keeps the editor open for the note.
        if moods.today == nil { isEditing = true }
        moods.setMood(mood)
    }
}

/// Which face of the card to show. A day with a mood is saved unless the user
/// is editing it; a day without one is always the editor.
enum MoodCardPhase: Equatable {
    case editing, saved

    init(entry: MoodEntry?, isEditing: Bool) {
        self = entry != nil && !isEditing ? .saved : .editing
    }
}

// MARK: - Saved

private struct MoodSavedContent: View {
    let entry: MoodEntry
    let onEdit: () -> Void
    let onChat: () -> Void
    /// The button says the mascot's name; reading it here re-draws on rename.
    @AppStorage(MascotName.storageKey) private var mascotName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                face
                summary
                Spacer(minLength: 0)
                editButton
            }
            // A small chip, not a full-width button: the card is about the
            // mood; chatting is the extra.
            Button(action: onChat) {
                HStack(spacing: 8) {
                    Image(entry.mood.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text(Strings.chatButton(named: mascotName))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(OneDay.inkSoft)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(OneDay.inkFaint)
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(OneDay.hairline).frame(height: 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mood-chat")
        }
    }

    private var face: some View {
        Button(action: onEdit) {
            Image(entry.mood.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .padding(6)
                .background(Circle().fill(Color.oneDayBrand.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.mood.label), \(Strings.moodEditFaceHint)")
        .accessibilityIdentifier("mood-saved-face")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Strings.moodSaved)
                .font(OneDay.Font.micro)
                .foregroundStyle(OneDay.inkSoft)
            Text(entry.mood.label)
                .font(OneDay.Font.headline)
                .foregroundStyle(OneDay.ink)
            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(OneDay.Font.subhead)
                    .foregroundStyle(OneDay.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var editButton: some View {
        Button(Strings.moodEdit, action: onEdit)
            .font(OneDay.Font.caption)
            .foregroundStyle(OneDay.brandText)
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 32)
            .background(OneDay.surfaceSoft, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityIdentifier("mood-edit")
    }
}

// MARK: - Editor

private struct MoodEditorContent: View {
    let today: MoodEntry?
    let onPick: (Mood) -> Void
    let onNote: (String) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.moodPrompt)
                .font(OneDay.Font.callout)
                .foregroundStyle(OneDay.ink)
            MoodFaceRow(selected: today?.mood, onPick: onPick)
            if let today {
                MoodNoteField(entry: today, onCommit: onNote)
                Button(Strings.moodDone, action: onDone)
                    .buttonStyle(.primaryAction)
                    .accessibilityIdentifier("mood-done")
            }
        }
    }
}

private struct MoodPrivateHint: View {
    var body: some View {
        Label(Strings.moodPrivateHint, systemImage: "lock.fill")
            .font(OneDay.Font.micro)
            .foregroundStyle(OneDay.inkFaint)
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
