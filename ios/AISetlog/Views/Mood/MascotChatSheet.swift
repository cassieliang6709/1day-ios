import SwiftUI

/// 和小方块聊两句. Opens with the mascot reacting to today's mood and note,
/// then a few turns back and forth (capped at `MoodStore.chatLimit`).
/// History is stored on this phone only.
struct MascotChatSheet: View {
    @Environment(MoodStore.self) private var moods
    @Environment(\.dismiss) private var dismiss
    var service: MascotChatting = RemoteMascotChatService()

    @State private var input = ""
    @State private var isWaiting = false
    /// Shown under the chat when a call fails. Not saved, so it never goes
    /// back to the model as something the mascot said.
    @State private var fallback: String?
    @AppStorage(MascotName.storageKey) private var savedName = ""
    @AppStorage(MascotName.askedKey) private var nameAsked = false
    @State private var naming = false
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MascotChatList(messages: moods.chat(), face: faceName,
                               isWaiting: isWaiting, fallback: fallback)
                inputBar
            }
            .background(OneDay.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button { askName() } label: {
                        HStack(spacing: 4) {
                            Text(Strings.moodChatTitle).font(.headline)
                            Image(systemName: "pencil").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(OneDay.ink)
                    }
                    .accessibilityHint(Strings.mascotRename)
                    .accessibilityIdentifier("mascot-name")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.moodChatClose) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert(Strings.mascotNameQuestion, isPresented: $naming) {
            TextField(Strings.mascotNamePlaceholder, text: $draftName)
            Button(Strings.mascotNameSave) { MascotName.save(draftName) }
            Button(Strings.mascotNameSkip, role: .cancel) { nameAsked = true }
        } message: {
            Text(Strings.mascotNameMessage)
        }
        .task {
            // Asked once, the first time the chat opens; the title renames it
            // after. The opening line waits for the answer so it uses the name.
            if !nameAsked {
                askName()
            } else if moods.chat().isEmpty {
                await askMascot()
            }
        }
        .onChange(of: naming) { _, open in
            if !open, moods.chat().isEmpty { Task { await askMascot() } }
        }
    }

    private func askName() {
        draftName = savedName
        naming = true
    }

    private var faceName: String { moods.today?.mood.imageName ?? Mood.calm.imageName }

    @ViewBuilder private var inputBar: some View {
        if moods.canSendChat() {
            MascotChatInput(text: $input, isWaiting: isWaiting, onSend: send)
        } else {
            Text(Strings.moodChatFull)
                .font(OneDay.Font.caption)
                .foregroundStyle(OneDay.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
    }

    private func send() {
        guard !isWaiting, moods.appendChat(.user, input) else { return }
        input = ""
        Task { await askMascot() }
    }

    private func askMascot() async {
        guard let today = moods.today else { return }
        isWaiting = true
        fallback = nil
        defer { isWaiting = false }
        do {
            let reply = try await service.reply(
                mood: today.mood, note: today.note, history: moods.chat(), language: AppLanguage.effective)
            moods.appendChat(.assistant, reply)
        } catch {
            fallback = Strings.moodChatFallback
        }
    }
}

private struct MascotChatList: View {
    let messages: [MascotChatMessage]
    let face: String
    let isWaiting: Bool
    let fallback: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { MascotBubble(role: $0.role, text: $0.content, face: face) }
                    if isWaiting { MascotBubble(role: .assistant, text: "…", face: face) }
                    if let fallback { MascotBubble(role: .assistant, text: fallback, face: face) }
                    Label(Strings.moodChatPrivate, systemImage: "lock.fill")
                        .font(OneDay.Font.micro)
                        .foregroundStyle(OneDay.inkFaint)
                        .frame(maxWidth: .infinity)
                        .id("bottom")
                }
                .padding(16)
            }
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
            .onChange(of: isWaiting) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
        }
    }
}

private struct MascotBubble: View {
    let role: MascotChatMessage.Role
    let text: String
    let face: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if role == .user { Spacer(minLength: 48) }
            if role == .assistant {
                Image(face).resizable().scaledToFit().frame(width: 32, height: 32)
            }
            Text(text)
                .font(OneDay.Font.body)
                .foregroundStyle(role == .user ? OneDay.onBrand : OneDay.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubble)
                .fixedSize(horizontal: false, vertical: true)
            if role == .assistant { Spacer(minLength: 48) }
        }
    }

    private var bubble: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(role == .user ? Color.oneDayBrand : OneDay.surface)
    }
}

private struct MascotChatInput: View {
    @Binding var text: String
    let isWaiting: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !isWaiting && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @State private var dictation = SpeechDictation()
    @State private var textBeforeDictation = ""
    /// Off once the message is sent, so a late final transcript can't refill the box.
    @State private var acceptsTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row
            DictationStatusLine(status: dictation.status)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(OneDay.surface)
        .onChange(of: dictation.transcript) { _, spoken in applyTranscript(spoken) }
        .onDisappear { dictation.stop() }
    }

    private var row: some View {
        HStack(spacing: 8) {
            TextField(Strings.moodChatPlaceholder, text: $text, axis: .vertical)
                .lineLimit(1...3)
                .font(OneDay.Font.subhead)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(OneDay.surfaceSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onSubmit(send)
                .accessibilityIdentifier("mascot-chat-input")
            MoodMicButton(isListening: dictation.isListening, action: toggleDictation)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(OneDay.onBrand)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.oneDayBrand))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.4)
            .accessibilityLabel(Strings.moodChatSend)
        }
    }

    private func send() {
        acceptsTranscript = false
        dictation.stop()
        onSend()
    }

    private func toggleDictation() {
        if !dictation.isListening {
            textBeforeDictation = text
            acceptsTranscript = true
        }
        Task { await dictation.toggle(language: AppLanguage.effective) }
    }

    private func applyTranscript(_ spoken: String) {
        guard acceptsTranscript, !spoken.isEmpty else { return }
        let base = textBeforeDictation
        let joiner = base.isEmpty || AppLanguage.effective.resolved == .chinese ? "" : " "
        text = base + joiner + spoken
    }
}
