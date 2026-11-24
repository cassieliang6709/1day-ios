import SwiftUI

struct DailyCheckInSheet: View {
    var prompt: String = Strings.moodPrompt
    var onFilm: (() -> Void)? = nil

    @Environment(MoodStore.self) private var moods
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 260

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        VStack(alignment: .leading, spacing: OneDay.Space.l) {
            Text(prompt)
                .font(OneDay.Font.headline)
                .foregroundStyle(OneDay.ink)

            HStack(spacing: OneDay.Space.xs) {
                ForEach(Mood.allCases) { mood in
                    MoodFaceButton(mood: mood, state: state(for: mood)) {
                        withAnimation(OneDay.Motion.snap) { moods.setMood(mood) }
                    }
                }
            }

            if let entry = moods.today {
                MoodNoteField(entry: entry) { moods.setNote($0) }
                    .transition(.opacity)
            }

            if let onFilm {
                Button(Strings.libraryFilmToday, systemImage: "camera.fill") {
                    dismiss()
                    onFilm()
                }
                .buttonStyle(.primaryAction)
                .accessibilityIdentifier("daily-checkin-film")
            } else if moods.today != nil {
                Button(Strings.moodDone) { dismiss() }
                    .buttonStyle(.primaryAction)
                    .transition(.opacity)
                    .accessibilityIdentifier("daily-checkin-done")
            }
        }
        .padding(OneDay.Space.xl)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(OneDay.surface)
        .accessibilityIdentifier("daily-checkin")
    }

    private func state(for mood: Mood) -> MoodFaceButton.State {
        guard let selected = moods.today?.mood else { return .idle }
        return selected == mood ? .selected : .dimmed
    }
}
