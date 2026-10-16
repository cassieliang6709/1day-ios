import SwiftUI
import UIKit

/// The one-line note under the faces, with a mic to say it instead of typing.
/// Tap the mic to start, tap again to stop; the live transcript is appended to
/// whatever was already typed.
struct MoodNoteField: View {
    let entry: MoodEntry
    let onCommit: (String) -> Void

    @State private var text = ""
    @State private var textBeforeDictation = ""
    @State private var dictation = SpeechDictation()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                field
                MoodMicButton(isListening: dictation.isListening, action: toggleDictation)
            }
            DictationStatusLine(status: dictation.status)
        }
        .onAppear { text = entry.note }
        .onChange(of: entry.day) { _, _ in text = entry.note }
        .onChange(of: dictation.transcript) { _, spoken in applyTranscript(spoken) }
        .onChange(of: dictation.isListening) { _, listening in if !listening { onCommit(text) } }
        .onDisappear {
            dictation.stop()
            onCommit(text)
        }
    }

    private var field: some View {
        TextField(Strings.moodNotePlaceholder, text: $text)
            .font(OneDay.Font.subhead)
            .foregroundStyle(OneDay.ink)
            .submitLabel(.done)
            .focused($focused)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(OneDay.surfaceSoft, in: RoundedRectangle(cornerRadius: OneDay.Radius.chip, style: .continuous))
            .onChange(of: focused) { _, isFocused in if !isFocused { onCommit(text) } }
            .onSubmit { onCommit(text) }
            .accessibilityIdentifier("mood-note")
    }

    private func toggleDictation() {
        if !dictation.isListening {
            focused = false
            textBeforeDictation = text
        }
        Task { await dictation.toggle(language: AppLanguage.effective) }
    }

    private func applyTranscript(_ spoken: String) {
        guard !spoken.isEmpty else { return }
        let base = textBeforeDictation
        let joiner = base.isEmpty || AppLanguage.effective.resolved == .chinese ? "" : " "
        text = String((base + joiner + spoken).prefix(120))
    }
}

private struct MoodMicButton: View {
    let isListening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(isListening ? OneDay.onBrand : OneDay.brandText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(isListening ? Color.oneDayBrand : OneDay.surfaceSoft))
                .symbolEffect(.pulse, isActive: isListening)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isListening ? Strings.moodMicStop : Strings.moodMicStart)
        .accessibilityIdentifier("mood-mic")
    }
}

private struct DictationStatusLine: View {
    let status: SpeechDictation.Status

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .listening:
            hint(Strings.moodMicListening)
        case .unavailable:
            hint(Strings.moodMicUnavailable)
        case .denied:
            HStack(spacing: 6) {
                hint(Strings.moodMicDenied)
                Button(Strings.moodOpenSettings, action: openSettings)
                    .font(OneDay.Font.micro)
                    .foregroundStyle(OneDay.brandText)
                    .frame(minHeight: 32)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(OneDay.Font.micro)
            .foregroundStyle(OneDay.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
