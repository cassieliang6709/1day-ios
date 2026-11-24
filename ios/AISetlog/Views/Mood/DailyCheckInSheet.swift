import SwiftUI

struct DailyCheckInSheet: View {
    var onFilm: (() -> Void)? = nil

    @Environment(MoodStore.self) private var moods
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppLanguage.storageKey) private var appLanguage: AppLanguage = .system

    var body: some View {
        VStack(alignment: .leading, spacing: OneDay.Space.l) {
            Text(Strings.moodPrompt)
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
            }
        }
        .padding(OneDay.Space.xl)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(onFilm == nil ? Self.noteOnlyHeight : Self.withFilmHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(OneDay.surface)
        .accessibilityIdentifier("daily-checkin")
    }

    private static let noteOnlyHeight: CGFloat = 260
    private static let withFilmHeight: CGFloat = 340

    private func state(for mood: Mood) -> MoodFaceButton.State {
        guard let selected = moods.today?.mood else { return .idle }
        return selected == mood ? .selected : .dimmed
    }
}
